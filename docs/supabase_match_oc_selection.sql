-- Anime Arena Secret OC Match Selection (Phase 3)
-- Run after the OC foundation/progression and online draft/RPS migrations.

alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('waiting', 'initiative', 'oc_selection', 'draft', 'battle', 'completed', 'cancelled'));

create table if not exists public.match_oc_options (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_character_id uuid not null references public.player_characters(id) on delete restrict,
  slot integer not null check (slot between 1 and 3),
  name_snapshot text not null,
  verse_id bigint not null references public.verses(id) on delete restrict,
  verse_name_snapshot text not null,
  overall_snapshot integer not null check (overall_snapshot between 1 and 99),
  power_score_snapshot integer not null check (power_score_snapshot >= 0),
  overall_cap_snapshot integer not null check (overall_cap_snapshot between 1 and 99),
  created_at timestamptz not null default now(),
  primary key (match_id, player_id, player_character_id),
  unique (match_id, player_id, slot)
);

-- This table is deliberately private. Browser roles receive no SELECT grant.
create table if not exists public.match_oc_selections (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_character_id uuid references public.player_characters(id) on delete restrict,
  verse_id bigint references public.verses(id) on delete restrict,
  base_overall integer check (base_overall between 1 and 99),
  base_power_score integer check (base_power_score >= 0),
  overall_cap integer check (overall_cap between 1 and 99),
  locked_at timestamptz not null default now(),
  revealed_at timestamptz,
  primary key (match_id, player_id),
  check (
    (player_character_id is null and verse_id is null and base_overall is null and base_power_score is null and overall_cap is null) or
    (player_character_id is not null and verse_id is not null and base_overall is not null and base_power_score is not null and overall_cap is not null)
  )
);

create index if not exists match_oc_options_match_player_idx on public.match_oc_options (match_id, player_id, slot);
create index if not exists match_oc_selections_match_idx on public.match_oc_selections (match_id);

alter table public.match_oc_options enable row level security;
alter table public.match_oc_selections enable row level security;

-- Private selections must never be available through Supabase Realtime before reveal.
-- RLS has no SELECT policy on this table, so Realtime cannot deliver its rows. Also
-- remove it from the normal table-list publication when that publication is not ALL TABLES.
do $$
begin
  if exists (
    select 1
    from pg_publication_tables pt
    join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'match_oc_selections'
      and p.puballtables = false
  ) then
    execute 'alter publication supabase_realtime drop table public.match_oc_selections';
  end if;
end;
$$;

drop policy if exists "Participants read match OC options" on public.match_oc_options;
create policy "Participants read match OC options" on public.match_oc_options
  for select to authenticated using (exists (
    select 1 from public.matches m
    where m.id = match_oc_options.match_id and (select auth.uid()) in (m.player_one_id, m.player_two_id)
  ));

revoke all on public.match_oc_options, public.match_oc_selections from public, anon, authenticated;
grant select on public.match_oc_options to authenticated;

create or replace function public.get_match_oc_selection_state(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  opponent_id uuid;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception using errcode = '42501', message = 'Match unavailable.';
  end if;
  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;

  return jsonb_build_object(
    'matchId', match_row.id,
    'status', match_row.status,
    'yourPlayerId', caller_id,
    'opponentPlayerId', opponent_id,
    'yourProfile', (select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url
    ) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url
    ) from public.profiles p where p.id = opponent_id),
    'yourOptions', coalesce((select jsonb_agg(jsonb_build_object(
      'characterId', o.player_character_id, 'slot', o.slot, 'name', o.name_snapshot,
      'verseId', o.verse_id, 'verseName', o.verse_name_snapshot,
      'overall', o.overall_snapshot, 'powerScore', o.power_score_snapshot,
      'overallCap', o.overall_cap_snapshot
    ) order by o.slot) from public.match_oc_options o where o.match_id = p_match_id and o.player_id = caller_id), '[]'::jsonb),
    'opponentOptions', coalesce((select jsonb_agg(jsonb_build_object(
      'characterId', o.player_character_id, 'slot', o.slot, 'name', o.name_snapshot,
      'verseId', o.verse_id, 'verseName', o.verse_name_snapshot,
      'overall', o.overall_snapshot, 'powerScore', o.power_score_snapshot,
      'overallCap', o.overall_cap_snapshot
    ) order by o.slot) from public.match_oc_options o where o.match_id = p_match_id and o.player_id = opponent_id), '[]'::jsonb),
    'yourSelectedCharacterId', (select s.player_character_id from public.match_oc_selections s where s.match_id = p_match_id and s.player_id = caller_id),
    'yourLocked', exists(select 1 from public.match_oc_selections s where s.match_id = p_match_id and s.player_id = caller_id),
    'opponentLocked', exists(select 1 from public.match_oc_selections s where s.match_id = p_match_id and s.player_id = opponent_id),
    'bothComplete', (select count(*) = 2 from public.match_oc_selections s where s.match_id = p_match_id)
  );
end;
$$;

create or replace function public.initialize_match_oc_selection(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception using errcode = '42501', message = 'Match unavailable.';
  end if;
  if match_row.status in ('oc_selection', 'draft', 'battle', 'completed') then
    return public.get_match_oc_selection_state(p_match_id);
  end if;
  if match_row.status <> 'initiative' or match_row.initiative_state <> 'revealed' or match_row.initiative_player_id is null then
    raise exception using errcode = '23514', message = 'Initiative must have a winner first.';
  end if;

  insert into public.match_oc_options (
    match_id, player_id, player_character_id, slot, name_snapshot, verse_id,
    verse_name_snapshot, overall_snapshot, power_score_snapshot, overall_cap_snapshot
  )
  select p_match_id, pc.owner_id, pc.id,
    row_number() over (partition by pc.owner_id order by pc.created_at, pc.id)::integer,
    pc.name, pc.verse_id, v.name, pc.overall, pc.power_score, pc.overall_cap
  from public.player_characters pc
  join public.verses v on v.id = pc.verse_id
  where pc.owner_id in (match_row.player_one_id, match_row.player_two_id)
    and pc.active = true and pc.equipped = true and pc.retired_at is null
  order by pc.owner_id, pc.created_at
  on conflict do nothing;

  -- Zero-OC participants are complete with an explicit private No OC row.
  insert into public.match_oc_selections (match_id, player_id)
  select p_match_id, participant.player_id
  from (values (match_row.player_one_id), (match_row.player_two_id)) participant(player_id)
  where not exists (
    select 1 from public.match_oc_options o where o.match_id = p_match_id and o.player_id = participant.player_id
  )
  on conflict (match_id, player_id) do nothing;

  update public.matches set status = 'oc_selection', action_version = action_version + 1, updated_at = now()
  where id = p_match_id;

  if (select count(*) from public.match_oc_selections where match_id = p_match_id) = 2 then
    perform public.initialize_match_draft(p_match_id);
  end if;
  return public.get_match_oc_selection_state(p_match_id);
end;
$$;

create or replace function public.submit_match_oc_selection(p_match_id uuid, p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  existing_character_id uuid;
  option_row public.match_oc_options%rowtype;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception using errcode = '42501', message = 'Match unavailable.';
  end if;
  if match_row.status <> 'oc_selection' then
    if match_row.status in ('draft', 'battle', 'completed') then return public.get_match_oc_selection_state(p_match_id); end if;
    raise exception using errcode = '23514', message = 'OC selection is not active.';
  end if;

  select player_character_id into existing_character_id from public.match_oc_selections
  where match_id = p_match_id and player_id = caller_id;
  if found then
    if existing_character_id = p_character_id then return public.get_match_oc_selection_state(p_match_id); end if;
    raise exception using errcode = '23514', message = 'Your OC selection is already locked.';
  end if;

  select * into option_row
  from public.match_oc_options
  where match_id = p_match_id
    and player_id = caller_id
    and player_character_id = p_character_id;
  if not found then
    raise exception using errcode = '42501', message = 'OC is not an option for this match.';
  end if;

  insert into public.match_oc_selections (
    match_id, player_id, player_character_id, verse_id, base_overall,
    base_power_score, overall_cap, locked_at
  ) values (
    p_match_id, caller_id, option_row.player_character_id, option_row.verse_id,
    option_row.overall_snapshot, option_row.power_score_snapshot,
    option_row.overall_cap_snapshot, now()
  );

  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;
  if (select count(*) from public.match_oc_selections where match_id = p_match_id) = 2 then
    perform public.initialize_match_draft(p_match_id);
  end if;
  return public.get_match_oc_selection_state(p_match_id);
end;
$$;

-- Replace the draft initializer so only completed OC selection can enter draft.
-- initiative_player_id remains the source of initial priority.
create or replace function public.initialize_match_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  active_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status in ('draft', 'battle', 'completed') then return; end if;
  if match_row.status <> 'oc_selection' or match_row.initiative_state <> 'revealed' or match_row.initiative_player_id is null
    or (select count(*) from public.match_oc_selections where match_id = p_match_id) <> 2 then
    raise exception 'OC selection must be complete before draft';
  end if;

  select count(*) into active_count from public.characters where active = true;
  if active_count < 10 then raise exception 'At least 10 active fighters are required to start an online draft'; end if;

  insert into public.match_players (match_id, player_id, player_number, balance) values
    (p_match_id, match_row.player_one_id, 1, 20), (p_match_id, match_row.player_two_id, 2, 20)
  on conflict (match_id, player_id) do nothing;

  insert into public.match_characters (match_id, character_id, draft_position)
  select p_match_id, selected.id, row_number() over ()::integer
  from (select id from public.characters where active = true order by random() limit 10) selected
  on conflict do nothing;

  if (select count(*) from public.match_characters where match_id = p_match_id) <> 10 then
    raise exception 'Unable to create a complete unique draft pool';
  end if;

  update public.matches set status = 'draft', current_draft_position = 1, draft_state = 'decision',
    current_bid = null, current_bidder_id = null, priority_player_id = match_row.initiative_player_id,
    tie_priority_player_id = case when match_row.initiative_player_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end,
    action_version = action_version + 1, updated_at = now()
  where id = p_match_id;
end;
$$;

revoke all on function public.initialize_match_oc_selection(uuid) from public;
revoke all on function public.submit_match_oc_selection(uuid, uuid) from public;
revoke all on function public.get_match_oc_selection_state(uuid) from public;
revoke all on function public.initialize_match_draft(uuid) from public;
grant execute on function public.initialize_match_oc_selection(uuid) to authenticated;
grant execute on function public.submit_match_oc_selection(uuid, uuid) to authenticated;
grant execute on function public.get_match_oc_selection_state(uuid) to authenticated;
grant execute on function public.initialize_match_draft(uuid) to authenticated;

notify pgrst, 'reload schema';
