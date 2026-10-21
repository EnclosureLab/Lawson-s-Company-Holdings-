-- Team chat for the Lawsons Landscaping employee portal.
-- Run this in the Supabase SQL Editor for project lblrmljsjimrrighqbdo.

create table if not exists public.employee_chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 1 and 1200),
  created_at timestamptz not null default now()
);

create index if not exists employee_chat_messages_created_at_idx
  on public.employee_chat_messages (created_at desc);

alter table public.employee_chat_messages enable row level security;

drop policy if exists "Approved team can read chat" on public.employee_chat_messages;
create policy "Approved team can read chat"
on public.employee_chat_messages for select to authenticated
using (
  exists (
    select 1 from public.employee_profiles p
    where p.user_id = auth.uid() and p.approved = true
  )
);

drop policy if exists "Approved team can send chat" on public.employee_chat_messages;
create policy "Approved team can send chat"
on public.employee_chat_messages for insert to authenticated
with check (
  user_id = auth.uid()
  and char_length(trim(message)) between 1 and 1200
  and exists (
    select 1 from public.employee_profiles p
    where p.user_id = auth.uid() and p.approved = true
  )
);

grant select, insert on public.employee_chat_messages to authenticated;


-- Private one-to-one messages between approved team members.
create table if not exists public.employee_direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 1 and 1200),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create index if not exists employee_direct_messages_pair_created_idx
  on public.employee_direct_messages (sender_id, recipient_id, created_at);

alter table public.employee_direct_messages enable row level security;

drop policy if exists "Approved users can read their direct messages" on public.employee_direct_messages;
create policy "Approved users can read their direct messages"
on public.employee_direct_messages for select to authenticated
using (
  (sender_id = auth.uid() or recipient_id = auth.uid())
  and exists (
    select 1 from public.employee_profiles p
    where p.user_id = auth.uid() and p.approved = true
  )
);

drop policy if exists "Approved managers can send direct messages" on public.employee_direct_messages;
create policy "Approved managers can send direct messages"
on public.employee_direct_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and char_length(trim(message)) between 1 and 1200
  and exists (
    select 1 from public.employee_profiles p
    where p.user_id = auth.uid() and p.approved = true and p.role = 'manager'
  )
  and exists (
    select 1 from public.employee_profiles p
    where p.user_id = recipient_id and p.approved = true and p.role = 'employee'
  )
);

grant select, insert on public.employee_direct_messages to authenticated;
