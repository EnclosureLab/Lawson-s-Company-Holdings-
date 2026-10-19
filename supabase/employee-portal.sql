-- Lawsons Landscaping employee portal database setup
-- Run this entire script once in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.employee_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'employee' check (role in ('employee','manager')),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.employee_tasks (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  job_address text not null default '',
  due_date date,
  status text not null default 'Assigned' check (status in ('Assigned','In progress','Completed')),
  notes text not null default '',
  pay_amount numeric(10,2) not null default 0 check (pay_amount >= 0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Create a profile automatically at signup. Only this exact owner email gets manager access.
create or replace function public.handle_new_employee_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.employee_profiles (user_id, display_name, role, approved)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', ''),
    case when lower(coalesce(new.email, '')) = 'lawsonhughes53@gmail.com' then 'manager' else 'employee' end,
    lower(coalesce(new.email, '')) = 'lawsonhughes53@gmail.com'
  )
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    role = case when lower(coalesce(new.email, '')) = 'lawsonhughes53@gmail.com' then 'manager' else public.employee_profiles.role end,
    approved = case when lower(coalesce(new.email, '')) = 'lawsonhughes53@gmail.com' then true else public.employee_profiles.approved end;
  return new;
end;
$function$;

drop trigger if exists on_auth_user_created_employee_profile on auth.users;
create trigger on_auth_user_created_employee_profile
after insert on auth.users
for each row execute function public.handle_new_employee_user();

-- Ensure existing accounts get profiles, then promote the owner if the account exists already.
insert into public.employee_profiles (user_id, display_name, role, approved)
select u.id, coalesce(u.raw_user_meta_data->>'display_name',''),
       case when lower(coalesce(u.email,'')) = 'lawsonhughes53@gmail.com' then 'manager' else 'employee' end,
       lower(coalesce(u.email,'')) = 'lawsonhughes53@gmail.com'
from auth.users u
on conflict (user_id) do update set
  role = case when exists (select 1 from auth.users u2 where u2.id = employee_profiles.user_id and lower(coalesce(u2.email,'')) = 'lawsonhughes53@gmail.com') then 'manager' else employee_profiles.role end,
  approved = case when exists (select 1 from auth.users u2 where u2.id = employee_profiles.user_id and lower(coalesce(u2.email,'')) = 'lawsonhughes53@gmail.com') then true else employee_profiles.approved end;

alter table public.employee_profiles enable row level security;
alter table public.employee_tasks enable row level security;

create or replace function public.is_approved_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from public.employee_profiles
    where user_id = auth.uid() and role = 'manager' and approved = true
  );
$function$;

drop policy if exists "profile read own or manager" on public.employee_profiles;
create policy "profile read own or manager" on public.employee_profiles
for select to authenticated
using (user_id = auth.uid() or public.is_approved_manager());

drop policy if exists "profile insert own pending" on public.employee_profiles;
create policy "profile insert own pending" on public.employee_profiles
for insert to authenticated
with check (user_id = auth.uid() and role = 'employee' and approved = false);

drop policy if exists "manager update profiles" on public.employee_profiles;
create policy "manager update profiles" on public.employee_profiles
for update to authenticated
using (public.is_approved_manager())
with check (public.is_approved_manager());

drop policy if exists "profile update own pending" on public.employee_profiles;
create policy "profile update own pending" on public.employee_profiles
for update to authenticated
using (user_id = auth.uid() and role = 'employee' and approved = false)
with check (user_id = auth.uid() and role = 'employee' and approved = false);

drop policy if exists "tasks read own or manager" on public.employee_tasks;
create policy "tasks read own or manager" on public.employee_tasks
for select to authenticated
using (employee_id = auth.uid() or public.is_approved_manager());

drop policy if exists "manager insert tasks" on public.employee_tasks;
create policy "manager insert tasks" on public.employee_tasks
for insert to authenticated
with check (public.is_approved_manager());

drop policy if exists "manager update tasks" on public.employee_tasks;
create policy "manager update tasks" on public.employee_tasks
for update to authenticated
using (public.is_approved_manager())
with check (public.is_approved_manager());

drop policy if exists "employee update own task" on public.employee_tasks;
create policy "employee update own task" on public.employee_tasks
for update to authenticated
using (employee_id = auth.uid())
with check (employee_id = auth.uid());

revoke update on public.employee_tasks from authenticated;
grant update (status, notes, updated_at) on public.employee_tasks to authenticated;

-- Explicitly allow authenticated clients to call the manager-check helper.
grant execute on function public.is_approved_manager() to authenticated;

-- Backfill any Auth users whose profile is missing; ordinary accounts remain pending.
insert into public.employee_profiles (user_id, display_name, role, approved)
select u.id,
       coalesce(u.raw_user_meta_data->>'display_name', ''),
       case when lower(coalesce(u.email, '')) = 'lawsonhughes53@gmail.com' then 'manager' else 'employee' end,
       lower(coalesce(u.email, '')) = 'lawsonhughes53@gmail.com'
from auth.users u
on conflict (user_id) do update
set role = case
      when exists (
        select 1 from auth.users owner_user
        where owner_user.id = employee_profiles.user_id
          and lower(coalesce(owner_user.email, '')) = 'lawsonhughes53@gmail.com'
      ) then 'manager'
      else employee_profiles.role
    end,
    approved = case
      when exists (
        select 1 from auth.users owner_user
        where owner_user.id = employee_profiles.user_id
          and lower(coalesce(owner_user.email, '')) = 'lawsonhughes53@gmail.com'
      ) then true
      else employee_profiles.approved
    end;

grant select, insert, update on public.employee_profiles to authenticated;
grant select, insert, update on public.employee_tasks to authenticated;
