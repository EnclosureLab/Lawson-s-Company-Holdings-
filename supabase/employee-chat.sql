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
