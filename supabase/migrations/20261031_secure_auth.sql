-- Secure GBD Research Hub: Supabase project bootstrap.
-- Run in Supabase SQL Editor (project administrator only).
-- Do not add passwords, email addresses, or secret API keys to this public repository.
-- IMPORTANT: This migration does NOT remove previously published GitHub copies.
begin;

create table if not exists public.project_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  added_at timestamptz not null default now()
);
alter table public.project_members enable row level security;
revoke all on table public.project_members from anon, authenticated;

create table if not exists public.login_otp_challenges (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  code_hash text not null,
  sent_at timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts integer not null default 0,
  primary key (user_id, session_id)
);
alter table public.login_otp_challenges enable row level security;
revoke all on table public.login_otp_challenges from anon, authenticated;

create table if not exists public.otp_verified_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  verified_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (user_id, session_id)
);
alter table public.otp_verified_sessions enable row level security;
revoke all on table public.otp_verified_sessions from anon, authenticated;

-- Called by the trusted server function under the service role only.
-- Atomic upsert prevents parallel resend attempts from bypassing the cooldown.
create or replace function public.secure_begin_email_otp(
  p_user_id uuid, p_session_id uuid, p_code_hash text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  if not exists (
    select 1 from public.project_members
    where user_id = p_user_id and active = true
  ) then
    return false;
  end if;

  insert into public.login_otp_challenges
    (user_id, session_id, code_hash, sent_at, expires_at, attempts)
  values
    (p_user_id, p_session_id, p_code_hash, now(), now() + interval '5 minutes', 0)
  on conflict (user_id, session_id) do update
    set code_hash = excluded.code_hash,
        sent_at = excluded.sent_at,
        expires_at = excluded.expires_at,
        attempts = 0
    where public.login_otp_challenges.sent_at < now() - interval '60 seconds';

  get diagnostics v_count = row_count;
  return v_count = 1;
end
$$;

-- Uses row locking to make OTP one-time and count failed attempts.
-- A successful OTP grants a short-lived, SESSION-SPECIFIC server-side authorization.
create or replace function public.secure_verify_email_otp(
  p_user_id uuid, p_session_id uuid, p_code_hash text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_challenge public.login_otp_challenges%rowtype;
begin
  if not exists (
    select 1 from public.project_members
    where user_id = p_user_id and active = true
  ) then
    return false;
  end if;

  select * into v_challenge
  from public.login_otp_challenges
  where user_id = p_user_id and session_id = p_session_id
  for update;

  if not found then return false; end if;
  if v_challenge.expires_at <= now() or v_challenge.attempts >= 5 then return false; end if;

  if v_challenge.code_hash <> p_code_hash then
    update public.login_otp_challenges
      set attempts = attempts + 1
    where user_id = p_user_id and session_id = p_session_id;
    return false;
  end if;

  delete from public.login_otp_challenges
    where user_id = p_user_id and session_id = p_session_id;

  insert into public.otp_verified_sessions
    (user_id, session_id, verified_at, expires_at)
  values
    (p_user_id, p_session_id, now(), now() + interval '30 minutes')
  on conflict (user_id, session_id) do update
    set verified_at = excluded.verified_at, expires_at = excluded.expires_at;
  return true;
end
$$;

create or replace function public.has_verified_recent_otp()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1 from public.project_members m
      join public.otp_verified_sessions s on s.user_id = m.user_id
      where m.user_id = (select auth.uid())
        and m.active = true
        and s.session_id::text = (select auth.jwt()->>'session_id')
        and s.expires_at > now()
    )
$$;

-- Identity-bound logout invalidates just the current OTP session.
create or replace function public.revoke_my_verified_session()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.otp_verified_sessions
  where user_id = (select auth.uid())
    and session_id::text = (select auth.jwt()->>'session_id');
$$;

revoke all on function public.secure_begin_email_otp(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.secure_verify_email_otp(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.secure_begin_email_otp(uuid,uuid,text) to service_role;
grant execute on function public.secure_verify_email_otp(uuid,uuid,text) to service_role;

revoke all on function public.has_verified_recent_otp() from public, anon;
grant execute on function public.has_verified_recent_otp() to authenticated;
revoke all on function public.revoke_my_verified_session() from public, anon;
grant execute on function public.revoke_my_verified_session() to authenticated;

-- Admin-only bucket creation; file upload must use the Supabase dashboard or service-role backend.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gbd-private', 'gbd-private', false, 52428800, array['text/csv','application/vnd.ms-excel','application/octet-stream'])
on conflict (id) do update set public = false;

drop policy if exists "gbd_private_otp_verified_read" on storage.objects;
create policy "gbd_private_otp_verified_read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'gbd-private'
  and name = 'gbd2023_low_physical_activity.csv'
  and (select public.has_verified_recent_otp())
);
-- No anonymous, INSERT, UPDATE or DELETE storage policies are installed.
commit;

-- After creating a user via Supabase Auth > Users, add the approved UUID only:
-- insert into public.project_members(user_id, active)
-- values ('<UUID-FROM-AUTH-USERS>', true);
-- Never put an email address or access credential in this public SQL file.
