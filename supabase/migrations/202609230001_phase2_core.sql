begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create extension if not exists pgcrypto with schema extensions;

create table public.couples (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'waiting' check (status in ('waiting', 'active')),
  created_at timestamptz not null default now()
);

create table public.couple_members (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  slot smallint not null check (slot in (1, 2)),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
  joined_at timestamptz not null default now(),
  primary key (couple_id, user_id),
  unique (user_id),
  unique (couple_id, slot)
);

create table private.couple_invitations (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  code_hash bytea not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check ((consumed_at is null) = (consumed_by is null))
);

create unique index couple_invitations_one_open_per_couple
  on private.couple_invitations(couple_id)
  where consumed_at is null and revoked_at is null;

create table public.moments (
  id uuid primary key,
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null,
  note text not null default '' check (char_length(note) <= 500),
  storage_path text not null unique,
  captured_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  upload_state text not null default 'pending' check (upload_state in ('pending', 'ready')),
  deleted_at timestamptz,
  unique (couple_id, id),
  foreign key (couple_id, author_id)
    references public.couple_members(couple_id, user_id) on delete restrict
);

create table public.reactions (
  couple_id uuid not null,
  moment_id uuid not null,
  user_id uuid not null,
  emoji text not null check (emoji in ('♡', '♥︎', '❤️', '😍', '🥰', '🌙')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (moment_id, user_id),
  foreign key (couple_id, moment_id)
    references public.moments(couple_id, id) on delete cascade,
  foreign key (couple_id, user_id)
    references public.couple_members(couple_id, user_id) on delete cascade
);

create table public.replies (
  id uuid primary key,
  couple_id uuid not null,
  moment_id uuid not null,
  author_id uuid not null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (couple_id, moment_id)
    references public.moments(couple_id, id) on delete cascade,
  foreign key (couple_id, author_id)
    references public.couple_members(couple_id, user_id) on delete cascade
);

create table private.pairing_attempts (
  kind text not null check (kind in ('user', 'ip')),
  subject_hash bytea not null,
  window_started timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  primary key (kind, subject_hash)
);

create table private.photo_cleanup_jobs (
  storage_path text primary key,
  moment_id uuid not null,
  state text not null default 'queued' check (state in ('queued', 'running', 'done', 'failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

create index couple_members_user_idx on public.couple_members(user_id);
create index moments_couple_page_idx on public.moments(couple_id, captured_at desc, id desc);
create index reactions_couple_moment_idx on public.reactions(couple_id, moment_id);
create index replies_moment_page_idx on public.replies(moment_id, created_at, id);
create index cleanup_jobs_due_idx on private.photo_cleanup_jobs(state, next_attempt_at);

create or replace function private.is_couple_member(target_couple_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.couple_members cm
    where cm.couple_id = target_couple_id
      and cm.user_id = (select auth.uid())
  );
$$;

create or replace function private.can_access_ready_moment(target_couple_id uuid, target_moment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_couple_member(target_couple_id)
    and exists (
      select 1 from public.moments m
      where m.couple_id = target_couple_id
        and m.id = target_moment_id
        and m.upload_state = 'ready'
        and m.deleted_at is null
    );
$$;

revoke all on function private.is_couple_member(uuid) from public, anon;
revoke all on function private.can_access_ready_moment(uuid, uuid) from public, anon;
grant execute on function private.is_couple_member(uuid) to authenticated;
grant execute on function private.can_access_ready_moment(uuid, uuid) to authenticated;

alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.moments enable row level security;
alter table public.reactions enable row level security;
alter table public.replies enable row level security;

create policy couples_select_members on public.couples
  for select to authenticated
  using (private.is_couple_member(id));

create policy couple_members_select_couple on public.couple_members
  for select to authenticated
  using (private.is_couple_member(couple_id));

create policy moments_select_couple on public.moments
  for select to authenticated
  using (
    deleted_at is null
    and private.is_couple_member(couple_id)
    and (upload_state = 'ready' or author_id = (select auth.uid()))
  );

create policy reactions_select_couple on public.reactions
  for select to authenticated
  using (private.can_access_ready_moment(couple_id, moment_id));

create policy replies_select_couple on public.replies
  for select to authenticated
  using (deleted_at is null and private.can_access_ready_moment(couple_id, moment_id));

revoke all on public.couples, public.couple_members, public.moments, public.reactions, public.replies from anon, authenticated;
grant select on public.couples, public.couple_members, public.moments, public.reactions, public.replies to authenticated;

create or replace function public.begin_moment(
  p_moment_id uuid,
  p_note text,
  p_captured_at timestamptz
)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  target_couple uuid;
  expected_path text;
  existing public.moments%rowtype;
  cleaned_note text := btrim(coalesce(p_note, ''));
begin
  if caller is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_moment_id is null or p_captured_at is null or char_length(cleaned_note) > 500 then
    raise exception 'invalid moment';
  end if;

  select cm.couple_id into target_couple
  from public.couple_members cm
  join public.couples c on c.id = cm.couple_id and c.status = 'active'
  where cm.user_id = caller;
  if target_couple is null then raise exception 'active couple required' using errcode = '42501'; end if;

  expected_path := target_couple::text || '/' || caller::text || '/' || p_moment_id::text || '.jpg';
  insert into public.moments(id, couple_id, author_id, note, storage_path, captured_at)
  values (p_moment_id, target_couple, caller, cleaned_note, expected_path, p_captured_at)
  on conflict (id) do nothing;

  select * into existing from public.moments where id = p_moment_id;
  if existing.author_id <> caller
     or existing.couple_id <> target_couple
     or existing.storage_path <> expected_path
     or existing.note <> cleaned_note
     or existing.captured_at <> p_captured_at then
    raise exception 'moment id is already in use' using errcode = '23505';
  end if;
  return next existing;
end;
$$;

create or replace function public.finalize_moment(p_moment_id uuid)
returns setof public.moments
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  target public.moments%rowtype;
begin
  if caller is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into target from public.moments where id = p_moment_id for update;
  if target.id is null or target.author_id <> caller or target.deleted_at is not null then
    raise exception 'moment unavailable' using errcode = '42501';
  end if;
  if target.upload_state = 'pending' and not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'moment-photos'
      and o.name = target.storage_path
      and coalesce((o.metadata ->> 'size')::bigint, 0) between 1 and 10485760
      and lower(coalesce(o.metadata ->> 'mimetype', '')) = 'image/jpeg'
  ) then
    raise exception 'photo upload is incomplete';
  end if;
  update public.moments set upload_state = 'ready', updated_at = now()
  where id = p_moment_id returning * into target;
  return next target;
end;
$$;

create or replace function public.set_reaction(p_moment_id uuid, p_emoji text, p_is_active boolean)
returns setof public.reactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  target_couple uuid;
  result public.reactions%rowtype;
begin
  if caller is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select m.couple_id into target_couple from public.moments m
  where m.id = p_moment_id and m.upload_state = 'ready' and m.deleted_at is null;
  if target_couple is null or not private.is_couple_member(target_couple) then
    raise exception 'moment unavailable' using errcode = '42501';
  end if;
  insert into public.reactions(couple_id, moment_id, user_id, emoji, is_active)
  values (target_couple, p_moment_id, caller, p_emoji, p_is_active)
  on conflict (moment_id, user_id) do update
    set emoji = excluded.emoji, is_active = excluded.is_active, updated_at = now()
  returning * into result;
  return next result;
end;
$$;

create or replace function public.create_reply(p_reply_id uuid, p_moment_id uuid, p_body text)
returns setof public.replies
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  target_couple uuid;
  cleaned_body text := btrim(coalesce(p_body, ''));
  result public.replies%rowtype;
begin
  if caller is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if char_length(cleaned_body) not between 1 and 2000 then raise exception 'invalid reply'; end if;
  select m.couple_id into target_couple from public.moments m
  where m.id = p_moment_id and m.upload_state = 'ready' and m.deleted_at is null;
  if target_couple is null or not private.is_couple_member(target_couple) then
    raise exception 'moment unavailable' using errcode = '42501';
  end if;
  insert into public.replies(id, couple_id, moment_id, author_id, body)
  values (p_reply_id, target_couple, p_moment_id, caller, cleaned_body)
  on conflict (id) do nothing;
  select * into result from public.replies where id = p_reply_id;
  if result.author_id <> caller or result.moment_id <> p_moment_id or result.body <> cleaned_body then
    raise exception 'reply id is already in use' using errcode = '23505';
  end if;
  return next result;
end;
$$;

create or replace function public.remove_moment(p_moment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare target public.moments%rowtype;
begin
  select * into target from public.moments where id = p_moment_id for update;
  if target.id is null or target.author_id <> auth.uid() then
    raise exception 'moment unavailable' using errcode = '42501';
  end if;
  update public.moments set deleted_at = now(), updated_at = now() where id = p_moment_id;
  insert into private.photo_cleanup_jobs(storage_path, moment_id)
  values (target.storage_path, target.id)
  on conflict (storage_path) do nothing;
end;
$$;

revoke all on function public.begin_moment(uuid, text, timestamptz) from public, anon;
revoke all on function public.finalize_moment(uuid) from public, anon;
revoke all on function public.set_reaction(uuid, text, boolean) from public, anon;
revoke all on function public.create_reply(uuid, uuid, text) from public, anon;
revoke all on function public.remove_moment(uuid) from public, anon;
grant execute on function public.begin_moment(uuid, text, timestamptz) to authenticated;
grant execute on function public.finalize_moment(uuid) to authenticated;
grant execute on function public.set_reaction(uuid, text, boolean) to authenticated;
grant execute on function public.create_reply(uuid, uuid, text) to authenticated;
grant execute on function public.remove_moment(uuid) to authenticated;

create or replace function public.create_pairing_invitation_internal(
  p_user_id uuid,
  p_code_hash text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_couple uuid;
  target_status text;
  target_creator uuid;
  expiry timestamptz := now() + interval '24 hours';
  cleaned_name text := btrim(coalesce(p_display_name, ''));
begin
  if p_user_id is null or p_code_hash !~ '^[0-9a-f]{64}$' or char_length(cleaned_name) not between 1 and 40 then
    raise exception 'invalid pairing request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select cm.couple_id into target_couple from public.couple_members cm where cm.user_id = p_user_id;
  if target_couple is null then
    insert into public.couples(created_by) values (p_user_id) returning id into target_couple;
    insert into public.couple_members(couple_id, user_id, slot, display_name)
      values (target_couple, p_user_id, 1, cleaned_name);
  else
    -- Redemption locks the invitation before the couple; rotation uses the same order.
    perform 1 from private.couple_invitations i
      where i.couple_id = target_couple and i.consumed_at is null and i.revoked_at is null
      for update;
    select c.status, c.created_by into target_status, target_creator
      from public.couples c where c.id = target_couple for update;
    if target_status <> 'waiting' or target_creator <> p_user_id then
      raise exception 'account is already paired';
    end if;
    update public.couple_members set display_name = cleaned_name
      where couple_id = target_couple and user_id = p_user_id;
    update private.couple_invitations set revoked_at = now()
      where couple_id = target_couple and consumed_at is null and revoked_at is null;
  end if;
  insert into private.couple_invitations(couple_id, created_by, code_hash, expires_at)
    values (target_couple, p_user_id, decode(p_code_hash, 'hex'), expiry);
  return jsonb_build_object('couple_id', target_couple, 'expires_at', expiry);
end;
$$;

create or replace function public.redeem_pairing_invitation_internal(
  p_user_id uuid,
  p_code_hash text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite private.couple_invitations%rowtype;
  existing_couple uuid;
  cleaned_name text := btrim(coalesce(p_display_name, ''));
begin
  if p_user_id is null or p_code_hash !~ '^[0-9a-f]{64}$' or char_length(cleaned_name) not between 1 and 40 then
    raise exception 'invitation unavailable';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select cm.couple_id into existing_couple from public.couple_members cm where cm.user_id = p_user_id;
  select * into invite from private.couple_invitations i
    where i.code_hash = decode(p_code_hash, 'hex') for update;

  if invite.id is not null and invite.consumed_by = p_user_id and existing_couple = invite.couple_id then
    return jsonb_build_object('couple_id', invite.couple_id, 'status', 'active');
  end if;
  if existing_couple is not null or invite.id is null or invite.created_by = p_user_id
     or invite.consumed_at is not null or invite.revoked_at is not null or invite.expires_at <= now() then
    raise exception 'invitation unavailable';
  end if;

  perform 1 from public.couples c where c.id = invite.couple_id and c.status = 'waiting' for update;
  if not found then raise exception 'invitation unavailable'; end if;
  insert into public.couple_members(couple_id, user_id, slot, display_name)
    values (invite.couple_id, p_user_id, 2, cleaned_name);
  update public.couples set status = 'active' where id = invite.couple_id;
  update private.couple_invitations
    set consumed_at = now(), consumed_by = p_user_id
    where id = invite.id;
  update private.couple_invitations set revoked_at = now()
    where couple_id = invite.couple_id and id <> invite.id and consumed_at is null and revoked_at is null;
  return jsonb_build_object('couple_id', invite.couple_id, 'status', 'active');
end;
$$;

create or replace function public.check_pairing_rate_limit_internal(
  p_kind text,
  p_subject_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare current_attempts integer;
begin
  if p_kind not in ('user', 'ip') or p_subject_hash !~ '^[0-9a-f]{64}$'
     or p_limit not between 1 and 100 or p_window_seconds not between 60 and 86400 then
    raise exception 'invalid rate limit request';
  end if;
  insert into private.pairing_attempts(kind, subject_hash, attempts)
    values (p_kind, decode(p_subject_hash, 'hex'), 1)
  on conflict (kind, subject_hash) do update set
    window_started = case
      when private.pairing_attempts.window_started + make_interval(secs => p_window_seconds) <= now() then now()
      else private.pairing_attempts.window_started end,
    attempts = case
      when private.pairing_attempts.window_started + make_interval(secs => p_window_seconds) <= now() then 1
      else private.pairing_attempts.attempts + 1 end
  returning attempts into current_attempts;
  return current_attempts <= p_limit;
end;
$$;

revoke all on function public.create_pairing_invitation_internal(uuid, text, text) from public, anon, authenticated;
revoke all on function public.redeem_pairing_invitation_internal(uuid, text, text) from public, anon, authenticated;
revoke all on function public.check_pairing_rate_limit_internal(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.create_pairing_invitation_internal(uuid, text, text) to service_role;
grant execute on function public.redeem_pairing_invitation_internal(uuid, text, text) to service_role;
grant execute on function public.check_pairing_rate_limit_internal(text, text, integer, integer) to service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('moment-photos', 'moment-photos', false, 10485760, array['image/jpeg'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy moment_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'moment-photos'
    and exists (
      select 1 from public.moments m
      where m.storage_path = name
        and m.deleted_at is null
        and private.is_couple_member(m.couple_id)
        and (m.upload_state = 'ready' or m.author_id = (select auth.uid()))
    )
  );

create policy moment_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'moment-photos'
    and owner_id = (select auth.uid())::text
    and exists (
      select 1 from public.moments m
      where m.storage_path = name
        and m.author_id = (select auth.uid())
        and m.upload_state = 'pending'
        and m.deleted_at is null
        and private.is_couple_member(m.couple_id)
    )
  );

create policy moonlit_broadcast_receive on realtime.messages
  for select to authenticated
  using (
    extension = 'broadcast'
    and realtime.topic() ~ '^couple:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    and private.is_couple_member(split_part(realtime.topic(), ':', 2)::uuid)
  );

create or replace function private.broadcast_diary_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare target_couple uuid;
begin
  if tg_op = 'DELETE' then
    target_couple := old.couple_id;
  else
    target_couple := new.couple_id;
  end if;
  perform realtime.send('{}'::jsonb, 'diary_changed', 'couple:' || target_couple::text, true);
  return null;
end;
$$;

create trigger moments_broadcast after insert or update or delete on public.moments
for each row execute function private.broadcast_diary_change();
create trigger reactions_broadcast after insert or update or delete on public.reactions
for each row execute function private.broadcast_diary_change();
create trigger replies_broadcast after insert or update or delete on public.replies
for each row execute function private.broadcast_diary_change();
create trigger members_broadcast after insert or update or delete on public.couple_members
for each row execute function private.broadcast_diary_change();

commit;
