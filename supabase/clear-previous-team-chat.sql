-- One-time action: permanently delete all existing messages from the shared team chat.
-- This does not delete employee accounts, tasks, or private direct messages.
-- Run in the Supabase SQL Editor for project lblrmljsjimrrighqbdo.
delete from public.employee_chat_messages;
