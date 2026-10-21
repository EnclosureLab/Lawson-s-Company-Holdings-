-- Lawson's Company Holdings notification foundation.
-- Run this script in the Supabase SQL Editor after reviewing the schema.
-- Push delivery requires a separately deployed server-side Web Push worker and VAPID secrets.
-- Exact 24-hour reminders require employee_tasks.due_at timestamptz; current portal uses due_date date only.

create table if not exists public.employee_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null,
  event_type text not null check (event_type in ('new_message','task_assigned','task_unassigned','task_updated','task_reminder')),
  title text not null,
  body text not null default '',
  related_type text,
  related_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  unique (recipient_id, event_key)
);

create index if not exists employee_notifications_recipient_created_idx
  on public.employee_notifications (recipient_id, created_at desc);
create index if not exists employee_notifications_unread_idx
  on public.employee_notifications (recipient_id, is_read) where is_read = false;

alter table public.employee_notifications enable row level security;
drop policy if exists "Employees can read own notifications" on public.employee_notifications;
create policy "Employees can read own notifications"
  on public.employee_notifications for select to authenticated
  using (recipient_id = auth.uid() and exists (
    select 1 from public.employee_profiles p where p.user_id = auth.uid() and p.approved = true
  ));
drop policy if exists "Employees can mark own notifications read" on public.employee_notifications;
create policy "Employees can mark own notifications read"
  on public.employee_notifications for update to authenticated
  using (recipient_id = auth.uid() and exists (
    select 1 from public.employee_profiles p where p.user_id = auth.uid() and p.approved = true
  ))
  with check (recipient_id = auth.uid() and exists (
    select 1 from public.employee_profiles p where p.user_id = auth.uid() and p.approved = true
  ));
grant select, update on public.employee_notifications to authenticated;

-- Device subscriptions are per browser/device. Actual delivery must be done server-side.
create table if not exists public.employee_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_secret text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.employee_push_subscriptions enable row level security;
drop policy if exists "Employees manage own push subscriptions" on public.employee_push_subscriptions;
create policy "Employees manage own push subscriptions"
  on public.employee_push_subscriptions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
grant select, insert, update, delete on public.employee_push_subscriptions to authenticated;

-- Notify an employee when a private message is inserted.
create or replace function public.notify_employee_direct_message()
returns trigger language plpgsql security definer set search_path = public
as $$
declare sender_name text;
begin
  select coalesce(display_name, 'Your manager') into sender_name
  from public.employee_profiles where user_id = new.sender_id;
  insert into public.employee_notifications(recipient_id,event_key,event_type,title,body,related_type,related_id)
  values(new.recipient_id,'direct-message:'||new.id::text,'new_message','You have a new message','Open the portal to read your private message.','message',new.id)
  on conflict (recipient_id,event_key) do nothing;
  return new;
end; $$;
drop trigger if exists employee_direct_message_notification on public.employee_direct_messages;
create trigger employee_direct_message_notification after insert on public.employee_direct_messages
for each row execute function public.notify_employee_direct_message();

-- Notify when a task is assigned, unassigned/reassigned, or its details change.
create or replace function public.notify_employee_task_change()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  task_title text;
  changed_fields text;
begin
  task_title := coalesce(new.title, old.title, 'Task');
  if tg_op = 'INSERT' then
    insert into public.employee_notifications(recipient_id,event_key,event_type,title,body,related_type,related_id)
    values(new.employee_id,'task-assigned:'||new.id::text||':'||new.created_at::text,'task_assigned','New task assigned: '||task_title,'A new task has been assigned to you.','task',new.id)
    on conflict (recipient_id,event_key) do nothing;
    return new;
  end if;
  if old.employee_id is distinct from new.employee_id then
    insert into public.employee_notifications(recipient_id,event_key,event_type,title,body,related_type,related_id)
    values(old.employee_id,'task-unassigned:'||new.id::text||':'||clock_timestamp()::text,'task_unassigned','Task removed: '||coalesce(old.title,'Task'),'This task has been removed from your assignments.','task',new.id)
    on conflict (recipient_id,event_key) do nothing;
    insert into public.employee_notifications(recipient_id,event_key,event_type,title,body,related_type,related_id)
    values(new.employee_id,'task-reassigned:'||new.id::text||':'||clock_timestamp()::text,'task_assigned','Task assigned: '||task_title,'A task has been assigned to you.','task',new.id)
    on conflict (recipient_id,event_key) do nothing;
    return new;
  end if;
  if old.title is distinct from new.title
     or old.job_address is distinct from new.job_address
     or old.due_date is distinct from new.due_date
     or old.status is distinct from new.status
     or old.notes is distinct from new.notes
     or old.pay_amount is distinct from new.pay_amount then
    changed_fields := concat_ws(', ',
      case when old.title is distinct from new.title then 'title' end,
      case when old.job_address is distinct from new.job_address then 'location' end,
      case when old.due_date is distinct from new.due_date then 'deadline' end,
      case when old.status is distinct from new.status then 'status' end,
      case when old.notes is distinct from new.notes then 'instructions' end,
      case when old.pay_amount is distinct from new.pay_amount then 'pay' end
    );
    insert into public.employee_notifications(recipient_id,event_key,event_type,title,body,related_type,related_id)
    values(new.employee_id,'task-updated:'||new.id::text||':'||clock_timestamp()::text,'task_updated','Task updated: '||task_title,'Changed: '||changed_fields||'. Open the portal to see the latest details.','task',new.id)
    on conflict (recipient_id,event_key) do nothing;
  end if;
  return new;
end; $$;
drop trigger if exists employee_task_notification_insert on public.employee_tasks;
create trigger employee_task_notification_insert after insert on public.employee_tasks
for each row execute function public.notify_employee_task_change();
drop trigger if exists employee_task_notification_update on public.employee_tasks;
create trigger employee_task_notification_update after update on public.employee_tasks
for each row execute function public.notify_employee_task_change();

-- Reminder scheduling is intentionally not enabled by this SQL alone:
-- employee_tasks currently uses due_date (date), not a deadline timestamp.
-- Add due_at timestamptz and deploy a scheduled server-side worker before enabling exact 24-hour reminders.
