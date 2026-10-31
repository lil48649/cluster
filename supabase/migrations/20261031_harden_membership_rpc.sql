-- Keep elevated membership lookup in unexposed app_private schema.
-- Only an authenticated user can ask whether THEIR OWN membership is active.
begin;
create or replace function app_private.is_current_member()
returns boolean language sql stable security definer set search_path = ''
as $member_private$
 select (select auth.uid()) is not null and exists(
  select 1 from app_private.project_members pm
  where pm.user_id = (select auth.uid()) and pm.active
 );
$member_private$;
revoke all on function app_private.is_current_member() from public, anon;
grant execute on function app_private.is_current_member() to authenticated;

create or replace function public.secure_my_membership()
returns boolean language sql stable security invoker set search_path = ''
as $member_public$
 select (select app_private.is_current_member())
$member_public$;
revoke all on function public.secure_my_membership() from public, anon;
grant execute on function public.secure_my_membership() to authenticated;
commit;