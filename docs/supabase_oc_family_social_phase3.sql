-- Anime Arena OC Family Social System - Phase 3: Family identity and branding
-- Run manually in the Supabase SQL Editor after:
--   1. docs/supabase_oc_family_social_phase1.sql
--   2. docs/supabase_oc_family_social_phase2.sql
--   3. docs/supabase_oc_images.sql
--
-- Family membership remains the existing active + equipped + non-retired OC
-- loadout. This migration stores only one optional branding record per normal,
-- persistent player and does not modify gameplay, progression, or matchmaking.

create table if not exists public.oc_families (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  tagline text,
  description text,
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Preserve and extend a compatible pre-existing one-row-per-owner table if a
-- deployment introduced it ahead of this reference migration.
alter table public.oc_families add column if not exists name text;
alter table public.oc_families add column if not exists tagline text;
alter table public.oc_families add column if not exists description text;
alter table public.oc_families add column if not exists logo_url text;
alter table public.oc_families add column if not exists created_at timestamptz not null default now();
alter table public.oc_families add column if not exists updated_at timestamptz not null default now();

create unique index if not exists oc_families_owner_id_key
  on public.oc_families(owner_id);

alter table public.oc_families
  drop constraint if exists oc_families_name_check;
alter table public.oc_families
  add constraint oc_families_name_check
  check (
    name is null
    or (
      name = btrim(name)
      and char_length(name) between 1 and 40
      and position(E'\n' in name) = 0
      and position(E'\r' in name) = 0
    )
  );

alter table public.oc_families
  drop constraint if exists oc_families_tagline_check;
alter table public.oc_families
  add constraint oc_families_tagline_check
  check (
    tagline is null
    or (
      tagline = btrim(tagline)
      and char_length(tagline) between 1 and 100
      and position(E'\n' in tagline) = 0
      and position(E'\r' in tagline) = 0
    )
  );

alter table public.oc_families
  drop constraint if exists oc_families_description_check;
alter table public.oc_families
  add constraint oc_families_description_check
  check (
    description is null
    or (description = btrim(description) and char_length(description) between 1 and 750)
  );

alter table public.oc_families
  drop constraint if exists oc_families_logo_url_check;
alter table public.oc_families
  add constraint oc_families_logo_url_check
  check (
    logo_url is null
    or (
      split_part(logo_url, '/', 1) = owner_id::text
      and split_part(logo_url, '/', 2) in ('family-logo.jpg', 'family-logo.png', 'family-logo.webp')
      and split_part(logo_url, '/', 3) = ''
    )
  );

-- Reuse the existing generic updated_at trigger helper introduced by the OC
-- foundation migration rather than creating another equivalent function.
drop trigger if exists set_oc_family_updated_at on public.oc_families;
create trigger set_oc_family_updated_at
  before update on public.oc_families
  for each row execute function public.set_player_character_updated_at();

alter table public.oc_families enable row level security;

-- Browser clients use explicit RPCs. Keeping table privileges revoked prevents
-- direct INSERT/UPDATE/DELETE and broad public reads even if a future RLS policy
-- is accidentally added too widely.
revoke all privileges on table public.oc_families from public;
revoke all privileges on table public.oc_families from anon;
revoke all privileges on table public.oc_families from authenticated;

-- Dedicated public logo bucket: 3 MB, JPG/PNG/WebP, publicly renderable.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'oc-family-logos',
  'oc-family-logos',
  true,
  3145728,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_manage_oc_family_logo(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and split_part(p_object_name, '/', 1) = auth.uid()::text
    and split_part(p_object_name, '/', 2) in ('family-logo.jpg', 'family-logo.png', 'family-logo.webp')
    and split_part(p_object_name, '/', 3) = ''
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.is_guest = false
        and p.is_system_player = false
    );
$$;

revoke all on function public.can_manage_oc_family_logo(text) from public;
revoke all on function public.can_manage_oc_family_logo(text) from anon;
revoke all on function public.can_manage_oc_family_logo(text) from authenticated;
grant execute on function public.can_manage_oc_family_logo(text) to authenticated;

drop policy if exists "Public OC Family logo read" on storage.objects;
drop policy if exists "OC Family logo owner insert" on storage.objects;
drop policy if exists "OC Family logo owner update" on storage.objects;
drop policy if exists "OC Family logo owner delete" on storage.objects;

create policy "Public OC Family logo read"
  on storage.objects for select
  to public
  using (bucket_id = 'oc-family-logos');

create policy "OC Family logo owner insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'oc-family-logos'
    and public.can_manage_oc_family_logo(name)
  );

create policy "OC Family logo owner update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'oc-family-logos'
    and owner_id::text = auth.uid()::text
    and public.can_manage_oc_family_logo(name)
  )
  with check (
    bucket_id = 'oc-family-logos'
    and public.can_manage_oc_family_logo(name)
  );

create policy "OC Family logo owner delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'oc-family-logos'
    and owner_id::text = auth.uid()::text
    and public.can_manage_oc_family_logo(name)
  );

-- Explicit owner read. Guests and the Administrator/system account are rejected
-- even if they can authenticate through the normal application shell.
create or replace function public.get_my_oc_family_identity()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  family_identity jsonb;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = caller_id
      and p.is_guest = false
      and p.is_system_player = false
  ) then
    raise exception using errcode = '42501', message = 'OC Family customization is unavailable for this profile.';
  end if;

  select jsonb_build_object(
    'name', f.name,
    'tagline', f.tagline,
    'description', f.description,
    'logoPath', f.logo_url,
    'createdAt', f.created_at,
    'updatedAt', f.updated_at
  )
  into family_identity
  from public.oc_families f
  where f.owner_id = caller_id;

  return family_identity;
end;
$$;

-- Server-authoritative upsert. owner_id is always derived from auth.uid(); the
-- client cannot nominate another family owner or persist an arbitrary URL.
create or replace function public.upsert_oc_family_identity(
  p_name text,
  p_tagline text,
  p_description text,
  p_logo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_name text := nullif(btrim(coalesce(p_name, '')), '');
  normalized_tagline text := nullif(btrim(coalesce(p_tagline, '')), '');
  normalized_description text := nullif(btrim(coalesce(p_description, '')), '');
  normalized_logo_path text := nullif(btrim(coalesce(p_logo_path, '')), '');
  saved_family public.oc_families%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  perform 1
  from public.profiles p
  where p.id = caller_id
    and p.is_guest = false
    and p.is_system_player = false
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'OC Family customization is unavailable for this profile.';
  end if;

  if normalized_name is not null and (
    char_length(normalized_name) > 40
    or position(E'\n' in normalized_name) > 0
    or position(E'\r' in normalized_name) > 0
  ) then
    raise exception using errcode = '22001', message = 'Family name cannot exceed 40 characters.';
  end if;

  if normalized_tagline is not null and (
    char_length(normalized_tagline) > 100
    or position(E'\n' in normalized_tagline) > 0
    or position(E'\r' in normalized_tagline) > 0
  ) then
    raise exception using errcode = '22001', message = 'Family tagline cannot exceed 100 characters.';
  end if;

  if normalized_description is not null and char_length(normalized_description) > 750 then
    raise exception using errcode = '22001', message = 'Family description cannot exceed 750 characters.';
  end if;

  if normalized_logo_path is not null and (
    split_part(normalized_logo_path, '/', 1) <> caller_id::text
    or split_part(normalized_logo_path, '/', 2) not in ('family-logo.jpg', 'family-logo.png', 'family-logo.webp')
    or split_part(normalized_logo_path, '/', 3) <> ''
    or not exists (
      select 1
      from storage.objects so
      where so.bucket_id = 'oc-family-logos'
        and so.name = normalized_logo_path
        and so.owner_id::text = caller_id::text
    )
  ) then
    raise exception using errcode = '23514', message = 'Invalid OC Family logo object.';
  end if;

  insert into public.oc_families as f (
    owner_id,
    name,
    tagline,
    description,
    logo_url
  ) values (
    caller_id,
    normalized_name,
    normalized_tagline,
    normalized_description,
    normalized_logo_path
  )
  on conflict (owner_id) do update set
    name = excluded.name,
    tagline = excluded.tagline,
    description = excluded.description,
    logo_url = excluded.logo_url
  returning f.* into saved_family;

  return jsonb_build_object(
    'name', saved_family.name,
    'tagline', saved_family.tagline,
    'description', saved_family.description,
    'logoPath', saved_family.logo_url,
    'createdAt', saved_family.created_at,
    'updatedAt', saved_family.updated_at
  );
end;
$$;

-- Replace the Phase 2 public-profile RPC with the same safe player and member
-- fields plus one nested Family identity object. It remains a single request and
-- excludes guests, the Administrator, inactive OCs, and retired OCs.
create or replace function public.get_public_player_profile(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  public_profile jsonb;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  with ranked_players as (
    select
      p.id,
      row_number() over (
        order by
          p.wins::numeric / nullif(p.wins + p.losses, 0) desc,
          p.wins desc,
          (p.wins + p.losses) desc,
          p.username asc,
          p.id asc
      ) as leaderboard_rank
    from public.profiles p
    where p.is_guest = false
      and (p.wins + p.losses) > 0
  ),
  family_members as (
    select
      row_number() over (order by pc.created_at asc, pc.id asc) as family_slot,
      pc.id,
      pc.name,
      pc.image_url,
      pc.verse_id,
      v.name as verse_name,
      v.slug as verse_slug,
      pc.oc_type,
      pc.starting_overall,
      pc.overall,
      pc.overall_cap,
      pc.power_score,
      pc.power_score_cap,
      pc.lore
    from public.player_characters pc
    join public.verses v on v.id = pc.verse_id
    where pc.owner_id = p_player_id
      and pc.active = true
      and pc.equipped = true
      and pc.retired_at is null
    order by pc.created_at asc, pc.id asc
    limit 3
  )
  select jsonb_build_object(
    'playerId', p.id,
    'displayName', p.username,
    'avatarUrl', p.avatar_url,
    'wins', p.wins,
    'losses', p.losses,
    'winRate', case
      when p.wins + p.losses = 0 then 0
      else round((p.wins::numeric * 100) / (p.wins + p.losses), 1)
    end,
    'rank', rp.leaderboard_rank,
    'joinedAt', p.created_at,
    'ocFamily', jsonb_build_object(
      'name', f.name,
      'tagline', f.tagline,
      'description', f.description,
      'logoPath', f.logo_url,
      'updatedAt', f.updated_at,
      'members', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'characterId', fm.id,
              'slot', fm.family_slot,
              'name', fm.name,
              'imageUrl', fm.image_url,
              'verseId', fm.verse_id,
              'verseName', fm.verse_name,
              'verseSlug', fm.verse_slug,
              'ocType', fm.oc_type,
              'startingOverall', fm.starting_overall,
              'overall', fm.overall,
              'overallCap', fm.overall_cap,
              'powerScore', fm.power_score,
              'powerScoreCap', fm.power_score_cap,
              'growth', fm.overall - fm.starting_overall,
              'lore', fm.lore
            )
            order by fm.family_slot
          )
          from family_members fm
        ),
        '[]'::jsonb
      )
    )
  )
  into public_profile
  from public.profiles p
  left join ranked_players rp on rp.id = p.id
  left join public.oc_families f on f.owner_id = p.id
  where p.id = p_player_id
    and p.is_guest = false
    and p.is_system_player = false;

  return public_profile;
end;
$$;

revoke all on function public.get_my_oc_family_identity() from public;
revoke all on function public.get_my_oc_family_identity() from anon;
revoke all on function public.get_my_oc_family_identity() from authenticated;
grant execute on function public.get_my_oc_family_identity() to authenticated;

revoke all on function public.upsert_oc_family_identity(text, text, text, text) from public;
revoke all on function public.upsert_oc_family_identity(text, text, text, text) from anon;
revoke all on function public.upsert_oc_family_identity(text, text, text, text) from authenticated;
grant execute on function public.upsert_oc_family_identity(text, text, text, text) to authenticated;

revoke all on function public.get_public_player_profile(uuid) from public;
revoke all on function public.get_public_player_profile(uuid) from anon;
revoke all on function public.get_public_player_profile(uuid) from authenticated;
grant execute on function public.get_public_player_profile(uuid) to authenticated;

notify pgrst, 'reload schema';
