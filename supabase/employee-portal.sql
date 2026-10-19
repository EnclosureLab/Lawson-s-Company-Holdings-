create table if not exists public.employee_profiles(user_id uuid primary key references auth.users(id) on delete cascade,display_name text not null default '',role text not null default 'employee' check(role in ('employee','manager')),approved boolean not null default false,created_at timestamptz not null default now());
create table if not exists public.employee_tasks(id uuid primary key default gen_random_uuid(),employee_id uuid not null references auth.users(id) on delete cascade,title text not null,job_address text not null default '',due_date date,status text not null default 'Assigned' check(status in ('Assigned','In progress','Completed')),notes text not null default '',pay_amount numeric(10,2) not null default 0 check(pay_amount>=0),created_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
-- Automatically create a profile whenever a new Supabase Auth user signs up.
-- The specified owner email is the only account automatically granted manager access.
create or replace function public.handle_new_employee_user() returns trigger
language plpgsql security definer set search_path=public
as $
begin
  insert into public.employee_profiles(user_id,display_name,role,approved)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name',''),
    case when lower(new.email)='lawsonhughes53@gmail.com' then 'manager' else 'employee' end,
    lower(new.email)='lawsonhughes53@gmail.com'
  )
  on conflict (user_id) do update set
    display_name=excluded.display_name,
    role=case when lower(new.email)='lawsonhughes53@gmail.com' then 'manager' else employee_profiles.role end,
    approved=case when lower(new.email)='lawsonhughes53@gmail.com' then true else employee_profiles.approved end;
  return new;
end;
$;
drop trigger if exists on_auth_user_created_employee_profile on auth.users;
create trigger on_auth_user_created_employee_profile
after insert on auth.users
for each row execute function public.handle_new_employee_user();

-- Promote the specified email if its account/profile already exists.
update public.employee_profiles p
set role='manager', approved=true
from auth.users u
where p.user_id=u.id and lower(u.email)='lawsonhughes53@gmail.com';

alter table public.employee_profiles enable row level security;alter table public.employee_tasks enable row level security;
create or replace function public.is_approved_manager() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.employee_profiles where user_id=auth.uid() and role='manager' and approved=true); $$;
drop policy if exists "profile read own or manager" on public.employee_profiles;create policy "profile read own or manager" on public.employee_profiles for select to authenticated using(user_id=auth.uid() or public.is_approved_manager());
drop policy if exists "profile insert own pending" on public.employee_profiles;create policy "profile insert own pending" on public.employee_profiles for insert to authenticated with check(user_id=auth.uid() and role='employee' and approved=false);
drop policy if exists "profile update own pending" on public.employee_profiles;create policy "profile update own pending" on public.employee_profiles for update to authenticated using(user_id=auth.uid() and role='employee' and approved=false) with check(user_id=auth.uid() and role='employee' and approved=false);
drop policy if exists "tasks read own or manager" on public.employee_tasks;create policy "tasks read own or manager" on public.employee_tasks for select to authenticated using(employee_id=auth.uid() or public.is_approved_manager());
drop policy if exists "manager insert tasks" on public.employee_tasks;create policy "manager insert tasks" on public.employee_tasks for insert to authenticated with check(public.is_approved_manager());
drop policy if exists "manager update tasks" on public.employee_tasks;create policy "manager update tasks" on public.employee_tasks for update to authenticated using(public.is_approved_manager()) with check(public.is_approved_manager());
drop policy if exists "employee update own task" on public.employee_tasks;create policy "employee update own task" on public.employee_tasks for update to authenticated using(employee_id=auth.uid()) with check(employee_id=auth.uid());
revoke update on public.employee_tasks from authenticated;grant update(status,notes,updated_at) on public.employee_tasks to authenticated;
-- After creating your own account, verify its user UUID in Authentication, then promote it:
-- update public.employee_profiles set role='manager', approved=true where user_id='YOUR-USER-UUID';
