-- Replace custom emailed OTP with Supabase's native TOTP MFA.
-- This is the only policy for the protected research CSV; aal1 is denied by RLS.
begin;
create or replace function app_private.can_read_gbd()
returns boolean
language sql stable security definer
set search_path = ''
as $gbd_mfa_access$
  select (select auth.uid()) is not null
    and (select auth.jwt()->>'aal') = 'aal2'
    and (select auth.jwt()->>'session_id') is not null
    and exists (
      select 1
      from app_private.project_members pm
      join auth.sessions sess on sess.user_id = pm.user_id
      join auth.mfa_factors factor on factor.user_id = pm.user_id
      where pm.user_id = (select auth.uid())
        and pm.active = true
        and sess.id::text = (select auth.jwt()->>'session_id')
        and sess.aal::text = 'aal2'
        and factor.factor_type::text = 'totp'
        and factor.status::text = 'verified'
    );
$gbd_mfa_access$;
revoke all on function app_private.can_read_gbd() from public, anon;
grant execute on function app_private.can_read_gbd() to authenticated;

-- The previous policy is replaced, never left as an additional OR grant.
drop policy if exists "project_member_email_otp_read_only" on storage.objects;
drop policy if exists "project_member_totp_mfa_read_only" on storage.objects;
create policy "project_member_totp_mfa_read_only"
on storage.objects for select to authenticated
using (
  bucket_id = 'gbd-private'
  and name = 'gbd2023_low_physical_activity.csv'
  and storage.allow_only_operation('object.get_authenticated')
  and (select app_private.can_read_gbd())
);

-- Remove external access to now-obsolete email-OTP bridge endpoints.
revoke execute on function public.secure_has_verified_otp() from public, anon, authenticated;
revoke execute on function public.secure_revoke_own_otp() from public, anon, authenticated;
commit;
