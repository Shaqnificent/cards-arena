-- Anime Arena OC Battle Integration / Reserve Fighter (Phase 5)
-- Run after supabase_oc_sacrifice.sql and the current online battle SQL.

alter table public.match_oc_preparations
  add column if not exists used_in_battle boolean not null default false,
  add column if not exists used_in_round integer check (used_in_round between 1 and 5);

alter table public.battle_selections
  add column if not exists selection_type text,
  add column if not exists player_character_id uuid references public.player_characters(id) on delete restrict;
update public.battle_selections set selection_type = 'canon' where selection_type is null;
alter table public.battle_selections alter column selection_type set not null;
alter table public.battle_selections alter column match_character_id drop not null;
alter table public.battle_selections drop constraint if exists battle_selections_selection_type_check;
alter table public.battle_selections add constraint battle_selections_selection_type_check check (
  (selection_type = 'canon' and match_character_id is not null and player_character_id is null) or
  (selection_type = 'oc' and match_character_id is null and player_character_id is not null)
);

alter table public.match_rounds
  alter column player_one_match_character_id drop not null,
  alter column player_two_match_character_id drop not null,
  add column if not exists player_one_fighter_type text,
  add column if not exists player_two_fighter_type text,
  add column if not exists player_one_player_character_id uuid references public.player_characters(id) on delete restrict,
  add column if not exists player_two_player_character_id uuid references public.player_characters(id) on delete restrict,
  add column if not exists player_one_name text,
  add column if not exists player_two_name text,
  add column if not exists player_one_overall bigint,
  add column if not exists player_two_overall bigint,
  add column if not exists player_one_power_score bigint,
  add column if not exists player_two_power_score bigint;

-- Backfill historical canon rounds before enforcing the generalized snapshot.
update public.match_rounds r set
  player_one_fighter_type = coalesce(r.player_one_fighter_type, 'canon'),
  player_two_fighter_type = coalesce(r.player_two_fighter_type, 'canon'),
  player_one_name = coalesce(r.player_one_name, c1.name),
  player_two_name = coalesce(r.player_two_name, c2.name),
  player_one_overall = coalesce(r.player_one_overall, c1.overall),
  player_two_overall = coalesce(r.player_two_overall, c2.overall),
  player_one_power_score = coalesce(r.player_one_power_score, c1.power_score),
  player_two_power_score = coalesce(r.player_two_power_score, c2.power_score)
from public.match_characters mc1, public.characters c1, public.match_characters mc2, public.characters c2
where mc1.id = r.player_one_match_character_id and c1.id = mc1.character_id
  and mc2.id = r.player_two_match_character_id and c2.id = mc2.character_id;

alter table public.match_rounds
  alter column player_one_fighter_type set not null,
  alter column player_two_fighter_type set not null,
  alter column player_one_name set not null,
  alter column player_two_name set not null,
  alter column player_one_overall set not null,
  alter column player_two_overall set not null,
  alter column player_one_power_score set not null,
  alter column player_two_power_score set not null;
alter table public.match_rounds drop constraint if exists match_rounds_fighter_sources_check;
alter table public.match_rounds add constraint match_rounds_fighter_sources_check check (
  ((player_one_fighter_type = 'canon' and player_one_match_character_id is not null and player_one_player_character_id is null) or
   (player_one_fighter_type = 'oc' and player_one_match_character_id is null and player_one_player_character_id is not null)) and
  ((player_two_fighter_type = 'canon' and player_two_match_character_id is not null and player_two_player_character_id is null) or
   (player_two_fighter_type = 'oc' and player_two_match_character_id is null and player_two_player_character_id is not null))
);

-- Selection rows remain private: no policies, grants, or Realtime publication.
revoke all on public.battle_selections from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_publication_tables pt join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public' and pt.tablename = 'battle_selections' and not p.puballtables)
  then execute 'alter publication supabase_realtime drop table public.battle_selections'; end if;
end $$;

create or replace function public.submit_battle_selection(p_match_id uuid, p_selection_type text, p_fighter_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); match_row public.matches%rowtype;
  selected_canon public.match_characters%rowtype; selected_oc public.match_oc_preparations%rowtype;
  one_selection public.battle_selections%rowtype; two_selection public.battle_selections%rowtype;
  one_name text; two_name text; one_overall bigint; two_overall bigint; one_power bigint; two_power bigint;
  round_winner uuid; next_one_score integer; next_two_score integer; final_winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'battle' or match_row.battle_state <> 'selecting' or match_row.current_battle_round is null then raise exception 'Selections are not open'; end if;

  if p_selection_type = 'canon' then
    select * into selected_canon from public.match_characters where id = p_fighter_id and match_id = p_match_id for update;
    if not found or selected_canon.owner_player_id <> caller_id then raise exception 'Fighter does not belong to this player'; end if;
    if selected_canon.used_in_battle then raise exception 'Fighter has already been used'; end if;
    if exists(select 1 from public.match_oc_preparations p where p.match_id = p_match_id and p.player_id = caller_id and p.sacrificed_match_character_id = selected_canon.id)
      then raise exception 'Sacrificed fighters cannot be used in battle'; end if;
    insert into public.battle_selections (match_id, round_number, player_id, selection_type, match_character_id)
      values (p_match_id, match_row.current_battle_round, caller_id, 'canon', selected_canon.id);
  elsif p_selection_type = 'oc' then
    select * into selected_oc from public.match_oc_preparations
      where match_id = p_match_id and player_id = caller_id and player_character_id = p_fighter_id for update;
    if not found or selected_oc.decision not in ('reserve', 'sacrifice') or selected_oc.match_overall is null or selected_oc.base_power_score is null then
      raise exception 'OC reserve is unavailable'; end if;
    if selected_oc.used_in_battle then raise exception 'OC has already been used'; end if;
    insert into public.battle_selections (match_id, round_number, player_id, selection_type, player_character_id)
      values (p_match_id, match_row.current_battle_round, caller_id, 'oc', selected_oc.player_character_id);
  else raise exception 'Invalid fighter selection type'; end if;

  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;
  select * into one_selection from public.battle_selections where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_one_id;
  select * into two_selection from public.battle_selections where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_two_id;
  if one_selection.player_id is null or two_selection.player_id is null then return; end if;

  -- Canon stats are currently read from public.characters when the round resolves.
  -- Match-level canon stat snapshots are future hardening; OC combat stats are
  -- already immutable match snapshots from match_oc_preparations.
  if one_selection.selection_type = 'canon' then
    select c.name, c.overall, c.power_score into one_name, one_overall, one_power from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = one_selection.match_character_id;
  else
    select o.name_snapshot, p.match_overall, p.base_power_score into one_name, one_overall, one_power
      from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id
      where p.match_id=p_match_id and p.player_id=match_row.player_one_id;
  end if;
  if two_selection.selection_type = 'canon' then
    select c.name, c.overall, c.power_score into two_name, two_overall, two_power from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = two_selection.match_character_id;
  else
    select o.name_snapshot, p.match_overall, p.base_power_score into two_name, two_overall, two_power
      from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id
      where p.match_id=p_match_id and p.player_id=match_row.player_two_id;
  end if;

  round_winner := case when one_overall > two_overall then match_row.player_one_id when two_overall > one_overall then match_row.player_two_id
    when one_power > two_power then match_row.player_one_id when two_power > one_power then match_row.player_two_id else null end;
  next_one_score := match_row.player_one_score + case when round_winner=match_row.player_one_id then 1 else 0 end;
  next_two_score := match_row.player_two_score + case when round_winner=match_row.player_two_id then 1 else 0 end;

  if one_selection.selection_type='canon' then update public.match_characters set used_in_battle=true where id=one_selection.match_character_id;
  else update public.match_oc_preparations set used_in_battle=true, used_in_round=match_row.current_battle_round, revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_one_id; end if;
  if two_selection.selection_type='canon' then update public.match_characters set used_in_battle=true where id=two_selection.match_character_id;
  else update public.match_oc_preparations set used_in_battle=true, used_in_round=match_row.current_battle_round, revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_two_id; end if;

  insert into public.match_rounds (match_id,round_number,winner_player_id,
    player_one_fighter_type,player_one_match_character_id,player_one_player_character_id,player_one_name,player_one_overall,player_one_power_score,
    player_two_fighter_type,player_two_match_character_id,player_two_player_character_id,player_two_name,player_two_overall,player_two_power_score)
  values (p_match_id,match_row.current_battle_round,round_winner,
    one_selection.selection_type,one_selection.match_character_id,one_selection.player_character_id,one_name,one_overall,one_power,
    two_selection.selection_type,two_selection.match_character_id,two_selection.player_character_id,two_name,two_overall,two_power);
  delete from public.battle_selections where match_id=p_match_id and round_number=match_row.current_battle_round;

  if next_one_score>=3 or next_two_score>=3 or match_row.current_battle_round=5 then
    final_winner := case when next_one_score>next_two_score then match_row.player_one_id when next_two_score>next_one_score then match_row.player_two_id else null end;
    update public.matches set status='completed',battle_state='complete',player_one_score=next_one_score,player_two_score=next_two_score,winner_id=final_winner,
      completed_at=now(),action_version=action_version+1,updated_at=now() where id=p_match_id and status='battle';
    if final_winner is not null then update public.profiles set wins=wins+1 where id=final_winner;
      update public.profiles set losses=losses+1 where id=case when final_winner=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end; end if;
  else update public.matches set battle_state='revealed',player_one_score=next_one_score,player_two_score=next_two_score,
    action_version=action_version+1,updated_at=now() where id=p_match_id; end if;
end;
$$;

-- Backward-compatible canon-only wrapper for older clients.
create or replace function public.submit_battle_selection(p_match_id uuid, p_match_character_id uuid)
returns void language sql security definer set search_path='' as $$
  select public.submit_battle_selection(p_match_id, 'canon', p_match_character_id);
$$;

create or replace function public.get_online_battle_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); match_row public.matches%rowtype; opponent_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id=p_match_id;
  if not found or caller_id not in (match_row.player_one_id,match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status not in ('battle','completed') then raise exception 'Battle is not available'; end if;
  opponent_id:=case when caller_id=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  return jsonb_build_object(
    'matchId',match_row.id,'status',match_row.status,'roundNumber',match_row.current_battle_round,'battleState',match_row.battle_state,
    'yourPlayerId',caller_id,'opponentPlayerId',opponent_id,
    'yourScore',case when caller_id=match_row.player_one_id then match_row.player_one_score else match_row.player_two_score end,
    'opponentScore',case when caller_id=match_row.player_one_id then match_row.player_two_score else match_row.player_one_score end,'matchWinnerId',match_row.winner_id,
    'yourProfile',(select jsonb_build_object('id',p.id,'username',p.username,'wins',p.wins,'losses',p.losses,'is_system_player',p.is_system_player)
      from public.profiles p where p.id=caller_id),
    'opponentProfile',(select jsonb_build_object('id',p.id,'username',p.username,'is_system_player',p.is_system_player)
      from public.profiles p where p.id=opponent_id),
    'yourTeam',coalesce((select jsonb_agg(jsonb_build_object('id',mc.id,'used',mc.used_in_battle,
      'sacrificed',exists(select 1 from public.match_oc_preparations prep where prep.match_id=p_match_id and prep.player_id=caller_id and prep.sacrificed_match_character_id=mc.id),
      'character',to_jsonb(c)||jsonb_build_object('verses',(select to_jsonb(v) from public.verses v where v.id=c.verse_id))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id=mc.character_id where mc.match_id=p_match_id and mc.owner_player_id=caller_id),'[]'::jsonb),
    'opponentTeam',coalesce((select jsonb_agg(jsonb_build_object('id',mc.id,'used',mc.used_in_battle,
      'character',to_jsonb(c)||jsonb_build_object('verses',(select to_jsonb(v) from public.verses v where v.id=c.verse_id))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id=mc.character_id where mc.match_id=p_match_id and mc.owner_player_id=opponent_id),'[]'::jsonb),
    'yourOC',(select case when p.player_character_id is null then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,
      'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',p.used_in_battle,
      'boost',p.sacrifice_boost,'decision',p.decision) end from public.match_oc_preparations p left join public.match_oc_options o
      on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=caller_id),
    'opponentOC',(select case when p.revealed_at is null then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,
      'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',p.used_in_battle,
      'decision',p.decision,'sacrificeTier',p.sacrifice_tier,'sacrificeBoost',p.sacrifice_boost,
      'sacrificedName',(select c.name from public.match_characters mc join public.characters c on c.id=mc.character_id where mc.id=p.sacrificed_match_character_id)) end
      from public.match_oc_preparations p left join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id
      where p.match_id=p_match_id and p.player_id=opponent_id),
    'yourSelection',(select jsonb_build_object('type',bs.selection_type,'id',coalesce(bs.match_character_id,bs.player_character_id)) from public.battle_selections bs
      where bs.match_id=p_match_id and bs.round_number=match_row.current_battle_round and bs.player_id=caller_id),
    'opponentLocked',exists(select 1 from public.battle_selections bs where bs.match_id=p_match_id and bs.round_number=match_row.current_battle_round and bs.player_id=opponent_id),
    'latestRound',(select jsonb_build_object('roundNumber',r.round_number,
      'yourFighter',case when caller_id=match_row.player_one_id then jsonb_build_object('type',r.player_one_fighter_type,'id',coalesce(r.player_one_match_character_id,r.player_one_player_character_id),'name',r.player_one_name,'overall',r.player_one_overall,'powerScore',r.player_one_power_score) else jsonb_build_object('type',r.player_two_fighter_type,'id',coalesce(r.player_two_match_character_id,r.player_two_player_character_id),'name',r.player_two_name,'overall',r.player_two_overall,'powerScore',r.player_two_power_score) end,
      'opponentFighter',case when caller_id=match_row.player_one_id then jsonb_build_object('type',r.player_two_fighter_type,'id',coalesce(r.player_two_match_character_id,r.player_two_player_character_id),'name',r.player_two_name,'overall',r.player_two_overall,'powerScore',r.player_two_power_score) else jsonb_build_object('type',r.player_one_fighter_type,'id',coalesce(r.player_one_match_character_id,r.player_one_player_character_id),'name',r.player_one_name,'overall',r.player_one_overall,'powerScore',r.player_one_power_score) end,
      'winnerPlayerId',r.winner_player_id) from public.match_rounds r where r.match_id=p_match_id order by r.round_number desc limit 1)
  );
end;
$$;

revoke all on function public.submit_battle_selection(uuid,text,uuid) from public;
revoke all on function public.submit_battle_selection(uuid,uuid) from public;
revoke all on function public.get_online_battle_state(uuid) from public;
grant execute on function public.submit_battle_selection(uuid,text,uuid) to authenticated;
grant execute on function public.submit_battle_selection(uuid,uuid) to authenticated;
grant execute on function public.get_online_battle_state(uuid) to authenticated;
notify pgrst,'reload schema';
