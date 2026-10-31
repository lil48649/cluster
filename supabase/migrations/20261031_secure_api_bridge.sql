-- Bridge functions applied to Supabase project after secure_gbd_backend_v2.
create or replace function public.secure_member_is_active(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $member$
 select exists(select 1 from app_private.project_members where user_id=p_user_id and active)
$member$;
revoke all on function public.secure_member_is_active(uuid) from public, anon, authenticated;
grant execute on function public.secure_member_is_active(uuid) to service_role;

create or replace function public.secure_has_verified_otp()
returns boolean language sql stable security invoker set search_path = ''
as $check$
 select (select app_private.can_read_gbd())
$check$;
revoke all on function public.secure_has_verified_otp() from public, anon;
grant execute on function public.secure_has_verified_otp() to authenticated;

create or replace function public.secure_revoke_own_otp()
returns void language plpgsql security definer set search_path = ''
as $revoke$
begin
 if (select auth.uid()) is null or (select auth.jwt()->>'session_id') is null then
   raise exception 'not authenticated';
 end if;
 delete from app_private.otp_session_grants
 where user_id=(select auth.uid())
   and session_id::text=(select auth.jwt()->>'session_id');
end
$revoke$;
revoke all on function public.secure_revoke_own_otp() from public, anon;
grant execute on function public.secure_revoke_own_otp() to authenticated;
