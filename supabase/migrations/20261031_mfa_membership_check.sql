-- Safe self-only membership check for the sign-in UI; no member enumeration.
begin;
create or replace function public.secure_my_membership()
returns boolean language sql stable security definer set search_path = ''
as $membership$
 select (select auth.uid()) is not null
 and exists (
    select 1 from app_private.project_members pm
    where pm.user_id = (select auth.uid()) and pm.active
 );
$membership$;
revoke all on function public.secure_my_membership() from public, anon;
grant execute on function public.secure_my_membership() to authenticated;
commit;