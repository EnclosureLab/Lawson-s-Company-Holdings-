-- Permanently delete a task from the employee portal.
-- Run this entire file in Supabase SQL Editor for project lblrmljsjimrrighqbdo.

create or replace function public.delete_employee_task(target_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to delete a task';
  end if;

  if not public.is_approved_manager() and not exists (
    select 1
      from public.employee_tasks
     where id = target_task_id
       and employee_id = auth.uid()
  ) then
    raise exception 'You can only delete tasks assigned to your account';
  end if;

  delete from public.employee_tasks where id = target_task_id;

  if not found then
    raise exception 'Task not found or already deleted';
  end if;
end;
$function$;

revoke all on function public.delete_employee_task(uuid) from public;
grant execute on function public.delete_employee_task(uuid) to authenticated;

notify pgrst, 'reload schema';
