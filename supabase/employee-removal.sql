-- Manager-only employee removal for the Lawsons Landscaping portal.
-- Run this script in the Supabase SQL Editor for project lblrmljsjimrrighqbdo.

create or replace function public.manager_remove_employee(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null or not public.is_approved_manager() then
    raise exception 'Only an approved manager can remove employees';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'You cannot remove your own manager account';
  end if;

  if not exists (
    select 1
    from public.employee_profiles
    where user_id = target_user_id
      and role = 'employee'
  ) then
    raise exception 'Employee account not found';
  end if;

  -- Remove assigned jobs and the portal profile. The Auth login itself is not
  -- deleted because the browser client cannot safely delete Auth users.
  delete from public.employee_tasks where employee_id = target_user_id;
  delete from public.employee_profiles where user_id = target_user_id and role = 'employee';
end;
$function$;

revoke all on function public.manager_remove_employee(uuid) from public;
grant execute on function public.manager_remove_employee(uuid) to authenticated;
