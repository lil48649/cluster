begin;
create or replace function public.secure_has_verified_mfa()
returns boolean language sql stable security invoker set search_path = ''
as $mfa_check$
 select (select app_private.can_read_gbd())
$mfa_check$;
revoke all on function public.secure_has_verified_mfa() from public, anon;
grant execute on function public.secure_has_verified_mfa() to authenticated;
commit;