-- Allow an approved manager to unassign a task while preserving its details and status.
-- Run the ENTIRE script in Supabase SQL Editor for project lblrmljsjimrrighqbdo.

alter table public.employee_tasks
  alter column employee_id drop not null;

create or replace function public.manager_unassign_task(target_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null or not public.is_approved_manager() then
    raise exception 'Only an approved manager can unassign tasks';
  end if;

  update public.employee_tasks
     set employee_id = null,
         updated_at = now()
   where id = target_task_id;

  if not found then
    raise exception 'Task not found';
  end if;
end;
$function$;

revoke all on function public.manager_unassign_task(uuid) from public;
grant execute on function public.manager_unassign_task(uuid) to authenticated;

-- Make the newly created RPC visible to PostgREST immediately.
notify pgrst, 'reload schema';
