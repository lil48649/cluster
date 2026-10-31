-- Allow only authenticated file download and its authenticated metadata preflight.
-- Both operations still require live AAL2 session, verified TOTP, and whitelist.
begin;
drop policy if exists "project_member_totp_mfa_read_only" on storage.objects;
create policy "project_member_totp_mfa_read_only"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'gbd-private'
  and name = 'gbd2023_low_physical_activity.csv'
  and storage.allow_any_operation(
    array['object.get_authenticated', 'object.get_authenticated_info']
  )
  and (select app_private.can_read_gbd())
);
commit;