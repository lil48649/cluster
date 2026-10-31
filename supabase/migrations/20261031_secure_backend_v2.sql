-- Secure GBD Research Hub database baseline.
-- Only server-side (service_role) may issue/verify OTP challenges.
-- Application users can read the SINGLE allowed private object only after
-- project membership + OTP + auth.sessions cross-check.
begin;
create schema if not exists app_private;
revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated, service_role;

create table if not exists app_private.project_members (
 user_id uuid primary key references auth.users(id) on delete cascade,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists app_private.otp_challenges (
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null,
 code_hash text not null,
 sent_at timestamptz not null default now(),
 expires_at timestamptz not null,
 attempts integer not null default 0 check (attempts between 0 and 5),
 primary key (user_id,session_id)
);
create table if not exists app_private.otp_session_grants (
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null,
 verified_at timestamptz not null default now(),
 expires_at timestamptz not null,
 primary key (user_id,session_id)
);
create table if not exists app_private.otp_send_quotas (
 user_id uuid primary key references auth.users(id) on delete cascade,
 period_start timestamptz not null default now(),
 send_count integer not null default 0
);
alter table app_private.project_members enable row level security;
alter table app_private.otp_challenges enable row level security;
alter table app_private.otp_session_grants enable row level security;
alter table app_private.otp_send_quotas enable row level security;

revoke all on all tables in schema app_private from public, anon, authenticated;
grant select, insert, update, delete on all tables in schema app_private to service_role;

create or replace function public.secure_begin_email_otp(
 p_user_id uuid,p_session_id uuid,p_code_hash text
) returns boolean
language plpgsql security invoker set search_path = ''
as $$
declare
 v_quota app_private.otp_send_quotas%rowtype;
begin
 if not exists(select 1 from app_private.project_members where user_id=p_user_id and active) then return false; end if;
 if not exists(select 1 from auth.sessions where id=p_session_id and user_id=p_user_id) then return false; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 9837));
 if exists(select 1 from app_private.otp_challenges
           where user_id=p_user_id and sent_at>now()-interval '60 seconds') then return false; end if;
 insert into app_private.otp_send_quotas(user_id) values (p_user_id)
 on conflict(user_id) do nothing;
 select * into v_quota from app_private.otp_send_quotas where user_id=p_user_id for update;
 if v_quota.period_start>now()-interval '1 hour' and v_quota.send_count>=10 then return false; end if;
 update app_private.otp_send_quotas set
 send_count=case when period_start<=now()-interval '1 hour' then 1 else send_count+1 end,
 period_start=case when period_start<=now()-interval '1 hour' then now() else period_start end
 where user_id=p_user_id;
 -- Invalidate other OTP codes for this user; new requests may only verify the latest code.
 delete from app_private.otp_challenges where user_id=p_user_id;
 insert into app_private.otp_challenges(user_id,session_id,code_hash,expires_at)
 values (p_user_id,p_session_id,p_code_hash,now()+interval '5 minutes');
 return true;
end $$;

create or replace function public.secure_verify_email_otp(
 p_user_id uuid,p_session_id uuid,p_code_hash text
) returns boolean
language plpgsql security invoker set search_path = ''
as $$
declare v app_private.otp_challenges%rowtype;
begin
 if not exists(select 1 from app_private.project_members where user_id=p_user_id and active) then return false; end if;
 if not exists(select 1 from auth.sessions where id=p_session_id and user_id=p_user_id) then return false; end if;
 select * into v from app_private.otp_challenges
 where user_id=p_user_id and session_id=p_session_id for update;
 if not found or v.expires_at<=now() or v.attempts>=5 then return false; end if;
 if v.code_hash<>p_code_hash then
   update app_private.otp_challenges set attempts=attempts+1
   where user_id=p_user_id and session_id=p_session_id;
   return false;
 end if;
 delete from app_private.otp_challenges where user_id=p_user_id and session_id=p_session_id;
 insert into app_private.otp_session_grants(user_id,session_id,expires_at)
 values(p_user_id,p_session_id,now()+interval '30 minutes')
 on conflict(user_id,session_id) do update
 set expires_at=excluded.expires_at, verified_at=now();
 return true;
end $$;

create or replace function public.secure_revoke_my_otp(
 p_user_id uuid,p_session_id uuid
) returns void
language sql security invoker set search_path = ''
as $$
 delete from app_private.otp_session_grants
 where user_id=p_user_id and session_id=p_session_id;
$$;

revoke execute on function public.secure_begin_email_otp(uuid,uuid,text) from public, anon, authenticated;
revoke execute on function public.secure_verify_email_otp(uuid,uuid,text) from public, anon, authenticated;
revoke execute on function public.secure_revoke_my_otp(uuid,uuid) from public, anon, authenticated;
grant execute on function public.secure_begin_email_otp(uuid,uuid,text) to service_role;
grant execute on function public.secure_verify_email_otp(uuid,uuid,text) to service_role;
grant execute on function public.secure_revoke_my_otp(uuid,uuid) to service_role;

create or replace function app_private.can_read_gbd()
returns boolean
language sql stable security definer set search_path = ''
as $$
 select (select auth.uid()) is not null
 and (select auth.jwt()->>'session_id') is not null
 and exists (
  select 1 from app_private.project_members pm
  join app_private.otp_session_grants grant_row on grant_row.user_id=pm.user_id
  join auth.sessions active_session
    on active_session.id=grant_row.session_id
   and active_session.user_id=pm.user_id
  where pm.user_id=(select auth.uid())
   and pm.active
   and grant_row.session_id::text=(select auth.jwt()->>'session_id')
   and grant_row.expires_at>now()
 );
$$;
revoke execute on function app_private.can_read_gbd() from public, anon;
grant execute on function app_private.can_read_gbd() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('gbd-private','gbd-private',false,52428800,
 array['text/csv','text/plain','application/vnd.ms-excel','application/octet-stream'])
on conflict(id) do update set public=false;

drop policy if exists "project_member_email_otp_read_only" on storage.objects;
create policy "project_member_email_otp_read_only" on storage.objects
 for select to authenticated using (
 bucket_id='gbd-private'
 and name='gbd2023_low_physical_activity.csv'
 and storage.allow_only_operation('object.get_authenticated')
 and (select app_private.can_read_gbd())
 );
commit;
