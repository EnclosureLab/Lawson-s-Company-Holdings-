-- One-time cleanup for duplicate employee chat messages.
-- Keeps the earliest row for each sender + exact message + minute.
-- Review the preview query first; then run the DELETE if the rows match the duplicates you want removed.

-- PREVIEW duplicate groups:
select user_id, message, date_trunc('minute', created_at) as message_minute, count(*) as copies,
       min(created_at) as first_sent_at
from public.employee_chat_messages
group by user_id, message, date_trunc('minute', created_at)
having count(*) > 1
order by first_sent_at;

-- DELETE extra copies while preserving the earliest record in each group:
with ranked as (
  select id,
         row_number() over (
           partition by user_id, message, date_trunc('minute', created_at)
           order by created_at asc, id asc
         ) as copy_number
  from public.employee_chat_messages
)
delete from public.employee_chat_messages as messages
using ranked
where messages.id = ranked.id
  and ranked.copy_number > 1;
