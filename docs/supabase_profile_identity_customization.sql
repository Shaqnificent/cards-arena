-- Anime Arena profile identity customization
-- Run after the current profiles, Boon Phase 1, OC Family Social Phase 3,
-- and OC leaderboard migrations. This migration assumes the current schema
-- includes profiles.is_admin, profiles.is_system_player, and profiles.boon_points.
-- It is focused on public identity only and does not alter competitive stats.

begin;

create temporary table profile_identity_migration_state (
  needs_backfill boolean not null
) on commit drop;

insert into profile_identity_migration_state (needs_backfill)
select not exists (
  select 1
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'profiles'
    and c.column_name = 'username_changes_remaining'
);

alter table public.profiles
  add column if not exists username_changes_remaining smallint not null default 3,
  add column if not exists avatar_mode text not null default 'initial',
  add column if not exists avatar_bg_color text not null default '#7C3AED',
  add column if not exists avatar_text_color text not null default '#FFFFFF';

create or replace function public.is_reserved_profile_username(p_username text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(btrim(coalesce(p_username, ''))) = any (array[
    'admin', 'administrator', 'animearena', 'system', 'support',
    'moderator', 'mod', 'owner', 'staff', 'official', 'developer',
    'security', 'root', 'null', 'undefined'
  ]::text[]);
$$;

create or replace function public.is_valid_profile_avatar_pair(
  p_background text,
  p_foreground text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (upper(coalesce(p_background, '')), upper(coalesce(p_foreground, ''))) in (
    ('#151126', '#FFFFFF'),
    ('#151126', '#FBBF24'),
    ('#151126', '#C4B5FD'),
    ('#151126', '#F9A8D4'),
    ('#C92A5B', '#FFFFFF'),
    ('#7C3AED', '#FFFFFF'),
    ('#D61F7C', '#FFFFFF'),
    ('#2563EB', '#FFFFFF'),
    ('#0891B2', '#11111A'),
    ('#059669', '#11111A'),
    ('#B7791F', '#11111A'),
    ('#6B7280', '#FFFFFF')
  );
$$;

-- Preserve the earliest valid case-insensitive name. Invalid, reserved, or
-- duplicate legacy names receive a stable sanitized name plus a UUID-derived
-- suffix. The collision loop makes this safe even in an unusual hash collision.
create temporary table profile_identity_username_backfill (
  profile_id uuid primary key,
  username text not null
) on commit drop;

do $$
declare
  profile_row record;
  candidate_base text;
  candidate text;
  collision_attempt integer;
begin
  for profile_row in
    select p.id, p.username, p.is_guest, p.is_system_player
    from public.profiles p
    order by p.created_at asc, p.id asc
  loop
    candidate_base := regexp_replace(btrim(coalesce(profile_row.username, '')), '[^A-Za-z0-9_]+', '_', 'g');
    candidate_base := regexp_replace(candidate_base, '^_+|_+$', '', 'g');
    candidate_base := left(candidate_base, 20);

    if candidate_base ~ '^[A-Za-z0-9_]{3,20}$'
      and (profile_row.is_system_player or not public.is_reserved_profile_username(candidate_base))
      and not exists (
        select 1 from profile_identity_username_backfill b
        where lower(b.username) = lower(candidate_base)
      )
    then
      candidate := candidate_base;
    else
      candidate_base := case
        when profile_row.is_guest then 'Guest'
        when candidate_base ~ '^[A-Za-z0-9_]{3,20}$' then left(candidate_base, 11)
        else 'Player'
      end;
      collision_attempt := 0;
      loop
        candidate := left(candidate_base, 11) || '_' || substr(
          md5(profile_row.id::text || ':' || collision_attempt::text), 1, 8
        );
        exit when not public.is_reserved_profile_username(candidate)
          and not exists (
            select 1 from profile_identity_username_backfill b
            where lower(b.username) = lower(candidate)
          );
        collision_attempt := collision_attempt + 1;
      end loop;
    end if;

    insert into profile_identity_username_backfill (profile_id, username)
    values (profile_row.id, candidate);
  end loop;
end
$$;

update public.profiles p
set username = b.username,
    username_changes_remaining = least(3, greatest(0, coalesce(p.username_changes_remaining, 3))),
    avatar_mode = case when nullif(btrim(p.avatar_url), '') is not null then 'google' else 'initial' end,
    avatar_bg_color = '#7C3AED',
    avatar_text_color = '#FFFFFF'
from profile_identity_username_backfill b
where b.profile_id = p.id
  and (select s.needs_backfill from profile_identity_migration_state s);

alter table public.profiles
  drop constraint if exists profiles_username_check,
  drop constraint if exists profiles_username_format_check,
  drop constraint if exists profiles_username_changes_remaining_check,
  drop constraint if exists profiles_avatar_mode_check,
  drop constraint if exists profiles_google_avatar_mode_check,
  drop constraint if exists profiles_avatar_bg_color_check,
  drop constraint if exists profiles_avatar_text_color_check,
  drop constraint if exists profiles_avatar_contrast_check;

alter table public.profiles
  add constraint profiles_username_format_check
    check (username = btrim(username) and username ~ '^[A-Za-z0-9_]{3,20}$'),
  add constraint profiles_username_changes_remaining_check
    check (username_changes_remaining between 0 and 3),
  add constraint profiles_avatar_mode_check
    check (avatar_mode in ('google', 'initial')),
  add constraint profiles_google_avatar_mode_check
    check (avatar_mode <> 'google' or nullif(btrim(avatar_url), '') is not null),
  add constraint profiles_avatar_bg_color_check
    check (avatar_bg_color ~ '^#[0-9A-F]{6}$'),
  add constraint profiles_avatar_text_color_check
    check (avatar_text_color ~ '^#[0-9A-F]{6}$'),
  add constraint profiles_avatar_contrast_check
    check (public.is_valid_profile_avatar_pair(avatar_bg_color, avatar_text_color));

create unique index if not exists profiles_username_case_insensitive_unique_idx
  on public.profiles (lower(username));

-- New accounts receive a format-safe unique username. Google identity metadata
-- initializes the profile once; subsequent Google logins never overwrite a
-- customized username because this trigger only inserts new profile rows.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_username text;
  username_base text;
  generated_avatar_url text;
  user_is_anonymous boolean;
  collision_attempt integer := 0;
begin
  user_is_anonymous := coalesce(new.is_anonymous, false);
  generated_avatar_url := case when user_is_anonymous then null else coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'avatar_url'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'picture'), '')
  ) end;

  username_base := case when user_is_anonymous then 'Guest' else coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Player'
  ) end;
  username_base := regexp_replace(username_base, '[^A-Za-z0-9_]+', '_', 'g');
  username_base := regexp_replace(username_base, '^_+|_+$', '', 'g');
  if username_base !~ '^[A-Za-z0-9_]{3,20}$' or public.is_reserved_profile_username(username_base) then
    username_base := case when user_is_anonymous then 'Guest' else 'Player' end;
  end if;
  username_base := left(username_base, 20);

  loop
    generated_username := case when collision_attempt = 0 then username_base
      else left(username_base, 11) || '_' || substr(md5(new.id::text || ':' || collision_attempt::text), 1, 8)
    end;
    begin
      insert into public.profiles (
        id, username, avatar_url, is_guest, username_changes_remaining,
        avatar_mode, avatar_bg_color, avatar_text_color
      ) values (
        new.id, generated_username, generated_avatar_url, user_is_anonymous, 3,
        case when generated_avatar_url is not null then 'google' else 'initial' end,
        '#7C3AED', '#FFFFFF'
      )
      on conflict (id) do nothing;
      exit;
    exception when unique_violation then
      collision_attempt := collision_attempt + 1;
    end;
  end loop;

  return new;
end;
$$;

create or replace function public.check_username_availability(p_username text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_username text := btrim(coalesce(p_username, ''));
  current_username text;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  select p.username into current_username from public.profiles p where p.id = caller_id;
  if current_username is null then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;
  if normalized_username !~ '^[A-Za-z0-9_]{3,20}$' then
    return jsonb_build_object('available', false, 'status', 'invalid', 'normalizedUsername', normalized_username);
  end if;
  if public.is_reserved_profile_username(normalized_username) then
    return jsonb_build_object('available', false, 'status', 'reserved', 'normalizedUsername', normalized_username);
  end if;
  if lower(normalized_username) = lower(current_username) then
    return jsonb_build_object('available', true, 'status', 'current', 'normalizedUsername', current_username);
  end if;
  if exists (select 1 from public.profiles p where lower(p.username) = lower(normalized_username)) then
    return jsonb_build_object('available', false, 'status', 'taken', 'normalizedUsername', normalized_username);
  end if;
  return jsonb_build_object('available', true, 'status', 'available', 'normalizedUsername', normalized_username);
end;
$$;

-- Username and avatar preferences commit in one transaction. Only an actual,
-- successful case-insensitive username change consumes one of the three changes.
create or replace function public.update_profile_identity(
  p_username text,
  p_avatar_mode text,
  p_avatar_bg_color text,
  p_avatar_text_color text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  normalized_username text := btrim(coalesce(p_username, ''));
  normalized_mode text := lower(btrim(coalesce(p_avatar_mode, '')));
  normalized_bg text := upper(btrim(coalesce(p_avatar_bg_color, '')));
  normalized_text text := upper(btrim(coalesce(p_avatar_text_color, '')));
  username_changed boolean;
  identity_changed boolean;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select * into profile_row from public.profiles p where p.id = caller_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;
  if profile_row.is_system_player then
    raise exception using errcode = '42501', message = 'System profile identity cannot be edited.';
  end if;
  if normalized_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception using errcode = '22023', message = 'Username must be 3-20 letters, numbers, or underscores.';
  end if;
  if public.is_reserved_profile_username(normalized_username) then
    raise exception using errcode = '22023', message = 'That username is reserved.';
  end if;
  if normalized_mode not in ('google', 'initial') then
    raise exception using errcode = '22023', message = 'Invalid avatar mode.';
  end if;
  if normalized_mode = 'google' and nullif(btrim(profile_row.avatar_url), '') is null then
    raise exception using errcode = '22023', message = 'No Google profile image is available.';
  end if;
  if normalized_bg !~ '^#[0-9A-F]{6}$' or normalized_text !~ '^#[0-9A-F]{6}$'
    or not public.is_valid_profile_avatar_pair(normalized_bg, normalized_text)
  then
    raise exception using errcode = '22023', message = 'Choose a supported avatar color combination.';
  end if;

  username_changed := lower(normalized_username) <> lower(profile_row.username);
  if username_changed and profile_row.username_changes_remaining <= 0 then
    raise exception using errcode = '22023', message = 'No username changes remaining.';
  end if;
  if username_changed and exists (
    select 1 from public.profiles p
    where p.id <> caller_id and lower(p.username) = lower(normalized_username)
  ) then
    raise exception using errcode = '23505', message = 'Username is already taken.';
  end if;

  identity_changed := username_changed
    or normalized_mode <> profile_row.avatar_mode
    or normalized_bg <> profile_row.avatar_bg_color
    or normalized_text <> profile_row.avatar_text_color;

  if identity_changed then
    begin
      update public.profiles p set
        username = case when username_changed then normalized_username else p.username end,
        username_changes_remaining = case when username_changed
          then p.username_changes_remaining - 1 else p.username_changes_remaining end,
        avatar_mode = normalized_mode,
        avatar_bg_color = normalized_bg,
        avatar_text_color = normalized_text
      where p.id = caller_id
      returning * into profile_row;
    exception when unique_violation then
      raise exception using errcode = '23505', message = 'Username is already taken.';
    end;
  end if;

  return jsonb_build_object(
    'status', case when identity_changed then 'updated' else 'no_change' end,
    'usernameChanged', username_changed,
    'username', profile_row.username,
    'usernameChangesRemaining', profile_row.username_changes_remaining,
    'avatarMode', profile_row.avatar_mode,
    'avatarUrl', profile_row.avatar_url,
    'avatarBgColor', profile_row.avatar_bg_color,
    'avatarTextColor', profile_row.avatar_text_color
  );
end;
$$;

-- Preserve the latest private profile contract and add only identity fields.
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare caller_id uuid := auth.uid();
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  return (
    select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'avatar_mode', p.avatar_mode,
      'avatar_bg_color', p.avatar_bg_color,
      'avatar_text_color', p.avatar_text_color,
      'username_changes_remaining', p.username_changes_remaining,
      'is_guest', p.is_guest,
      'is_admin', p.is_admin,
      'is_system_player', p.is_system_player,
      'wins', p.wins,
      'losses', p.losses,
      'created_at', p.created_at,
      'boon_points', p.boon_points
    )
    from public.profiles p where p.id = caller_id
  );
end;
$$;

-- Preserve the OC Family Social Phase 3 profile projection. Avatar preferences
-- are public; the rename counter is returned only to the profile owner.
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
    select p.id, row_number() over (
      order by p.wins::numeric / nullif(p.wins + p.losses, 0) desc,
        p.wins desc, (p.wins + p.losses) desc, p.username asc, p.id asc
    ) as leaderboard_rank
    from public.profiles p
    where p.is_guest = false and (p.wins + p.losses) > 0
  ),
  family_members as (
    select row_number() over (order by pc.created_at asc, pc.id asc) as family_slot,
      pc.id, pc.name, pc.image_url, pc.verse_id, v.name as verse_name, v.slug as verse_slug,
      pc.oc_type, pc.starting_overall, pc.overall, pc.overall_cap,
      pc.power_score, pc.power_score_cap, pc.lore
    from public.player_characters pc
    join public.verses v on v.id = pc.verse_id
    where pc.owner_id = p_player_id and pc.active = true and pc.equipped = true and pc.retired_at is null
    order by pc.created_at asc, pc.id asc limit 3
  )
  select jsonb_build_object(
    'playerId', p.id,
    'displayName', p.username,
    'avatarUrl', p.avatar_url,
    'avatarMode', p.avatar_mode,
    'avatarBgColor', p.avatar_bg_color,
    'avatarTextColor', p.avatar_text_color,
    'usernameChangesRemaining', case when caller_id = p.id then p.username_changes_remaining else null end,
    'wins', p.wins,
    'losses', p.losses,
    'winRate', case when p.wins + p.losses = 0 then 0
      else round((p.wins::numeric * 100) / (p.wins + p.losses), 1) end,
    'rank', rp.leaderboard_rank,
    'joinedAt', p.created_at,
    'ocFamily', jsonb_build_object(
      'name', f.name, 'tagline', f.tagline, 'description', f.description,
      'logoPath', f.logo_url, 'updatedAt', f.updated_at,
      'members', coalesce((select jsonb_agg(jsonb_build_object(
        'characterId', fm.id, 'slot', fm.family_slot, 'name', fm.name, 'imageUrl', fm.image_url,
        'verseId', fm.verse_id, 'verseName', fm.verse_name, 'verseSlug', fm.verse_slug,
        'ocType', fm.oc_type, 'startingOverall', fm.starting_overall, 'overall', fm.overall,
        'overallCap', fm.overall_cap, 'powerScore', fm.power_score, 'powerScoreCap', fm.power_score_cap,
        'growth', fm.overall - fm.starting_overall, 'lore', fm.lore
      ) order by fm.family_slot) from family_members fm), '[]'::jsonb)
    )
  ) into public_profile
  from public.profiles p
  left join ranked_players rp on rp.id = p.id
  left join public.oc_families f on f.owner_id = p.id
  where p.id = p_player_id and p.is_guest = false and p.is_system_player = false;

  return public_profile;
end;
$$;

-- Keep existing OC leaderboard behavior and add reusable avatar identity fields.
create or replace function public.get_oc_individual_leaderboard(
  p_sort text default 'overall', p_limit integer default 100, p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  if p_sort not in ('overall','power','growth') then raise exception using errcode='22023', message='Invalid OC leaderboard sort.'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 then raise exception using errcode='22023', message='Invalid pagination.'; end if;
  with ranked as (
    select row_number() over (order by
      case when p_sort='overall' then pc.overall end desc nulls last,
      case when p_sort='overall' then pc.power_score end desc nulls last,
      case when p_sort='power' then pc.power_score end desc nulls last,
      case when p_sort='power' then pc.overall end desc nulls last,
      case when p_sort='growth' then pc.overall-pc.starting_overall end desc nulls last,
      case when p_sort='growth' then pc.overall end desc nulls last,
      case when p_sort='growth' then pc.power_score end desc nulls last,
      pc.created_at asc, pc.id asc) as rank,
      pc.id, pc.name, pc.image_url, pc.starting_overall, pc.overall, pc.overall_cap,
      pc.power_score, pc.power_score_cap, pc.overall-pc.starting_overall as growth,
      pc.owner_id, p.username, p.avatar_url, p.avatar_mode, p.avatar_bg_color, p.avatar_text_color,
      pc.verse_id, v.name as verse_name
    from public.player_characters pc join public.profiles p on p.id=pc.owner_id
      join public.verses v on v.id=pc.verse_id
    where pc.active=true and pc.retired_at is null and p.is_guest=false
  ), page as (select * from ranked order by rank limit p_limit offset p_offset)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,'id',id,'name',name,'imageUrl',image_url,'ownerId',owner_id,'ownerUsername',username,
    'ownerAvatarUrl',avatar_url,'ownerAvatarMode',avatar_mode,'ownerAvatarBgColor',avatar_bg_color,
    'ownerAvatarTextColor',avatar_text_color,'verseId',verse_id,'verseName',verse_name,
    'startingOverall',starting_overall,'overall',overall,'overallCap',overall_cap,
    'powerScore',power_score,'powerScoreCap',power_score_cap,'growth',growth
  ) order by rank),'[]'::jsonb) into result from page;
  return result;
end;
$$;

create or replace function public.get_oc_family_leaderboard(
  p_sort text default 'overall', p_limit integer default 100, p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  if p_sort not in ('overall','power','growth') then raise exception using errcode='22023', message='Invalid OC family sort.'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 then raise exception using errcode='22023', message='Invalid pagination.'; end if;
  with eligible as (
    select pc.owner_id, p.username, p.avatar_url, p.avatar_mode, p.avatar_bg_color, p.avatar_text_color,
      count(*)::integer family_size, avg(pc.overall)::numeric avg_overall,
      avg(pc.power_score)::numeric avg_power_score,
      sum(pc.overall-pc.starting_overall)::bigint total_growth,
      jsonb_agg(jsonb_build_object('id',pc.id,'name',pc.name,'verseId',pc.verse_id,'verseName',v.name,
        'startingOverall',pc.starting_overall,'overall',pc.overall,'powerScore',pc.power_score,
        'growth',pc.overall-pc.starting_overall) order by pc.overall desc,pc.id) family
    from public.player_characters pc join public.profiles p on p.id=pc.owner_id
      join public.verses v on v.id=pc.verse_id
    where pc.active=true and pc.equipped=true and pc.retired_at is null and p.is_guest=false
    group by pc.owner_id,p.username,p.avatar_url,p.avatar_mode,p.avatar_bg_color,p.avatar_text_color
    having count(*)=3
  ), ranked as (
    select row_number() over (order by
      case when p_sort='overall' then avg_overall end desc nulls last,
      case when p_sort='overall' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_overall end desc nulls last,
      case when p_sort='growth' then total_growth end desc nulls last,
      case when p_sort='growth' then avg_overall end desc nulls last,
      case when p_sort='growth' then avg_power_score end desc nulls last,
      owner_id asc) as rank, * from eligible
  ), page as (select * from ranked order by rank limit p_limit offset p_offset)
  select coalesce(jsonb_agg(jsonb_build_object('rank',rank,'ownerId',owner_id,'username',username,
    'avatarUrl',avatar_url,'avatarMode',avatar_mode,'avatarBgColor',avatar_bg_color,
    'avatarTextColor',avatar_text_color,'familySize',family_size,'avgOverall',avg_overall,
    'avgPowerScore',avg_power_score,'totalGrowth',total_growth,'family',family
  ) order by rank),'[]'::jsonb) into result from page;
  return result;
end;
$$;

-- Identity presentation fields are public to authenticated players. The rename
-- counter remains private to get_my_profile / the owner perspective RPC.
revoke select on table public.profiles from anon, authenticated;
grant select (
  id, username, avatar_url, avatar_mode, avatar_bg_color, avatar_text_color,
  is_guest, is_admin, is_system_player, wins, losses, created_at
) on public.profiles to authenticated;

revoke update (username, avatar_url, username_changes_remaining, avatar_mode, avatar_bg_color, avatar_text_color)
  on public.profiles from public, anon, authenticated;

revoke all on function public.is_reserved_profile_username(text) from public, anon, authenticated;
revoke all on function public.is_valid_profile_avatar_pair(text, text) from public, anon, authenticated;
revoke all on function public.check_username_availability(text) from public, anon, authenticated;
revoke all on function public.update_profile_identity(text, text, text, text) from public, anon, authenticated;
revoke all on function public.get_my_profile() from public, anon;
revoke all on function public.get_public_player_profile(uuid) from public, anon, authenticated;
revoke all on function public.get_oc_individual_leaderboard(text,integer,integer) from public, anon, authenticated;
revoke all on function public.get_oc_family_leaderboard(text,integer,integer) from public, anon, authenticated;

grant execute on function public.check_username_availability(text) to authenticated;
grant execute on function public.update_profile_identity(text, text, text, text) to authenticated;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_public_player_profile(uuid) to authenticated;
grant execute on function public.get_oc_individual_leaderboard(text,integer,integer) to authenticated;
grant execute on function public.get_oc_family_leaderboard(text,integer,integer) to authenticated;

notify pgrst, 'reload schema';

commit;
