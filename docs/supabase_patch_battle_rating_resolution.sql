-- Run in the Supabase SQL Editor on projects that already installed
-- supabase_online_battle.sql. Safe to rerun: this only replaces the resolver RPC.
create or replace function public.submit_battle_selection(p_match_id uuid, p_match_character_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  selected_row public.match_characters%rowtype;
  one_selection uuid;
  two_selection uuid;
  one_overall integer;
  two_overall integer;
  one_power integer;
  two_power integer;
  round_winner uuid;
  next_one_score integer;
  next_two_score integer;
  final_winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'battle' or match_row.battle_state <> 'selecting' or match_row.current_battle_round is null then raise exception 'Selections are not open'; end if;

  select * into selected_row from public.match_characters
  where id = p_match_character_id and match_id = p_match_id for update;
  if not found or selected_row.owner_player_id <> caller_id then raise exception 'Fighter does not belong to this player'; end if;
  if selected_row.used_in_battle then raise exception 'Fighter has already been used'; end if;

  insert into public.battle_selections (match_id, round_number, player_id, match_character_id)
  values (p_match_id, match_row.current_battle_round, caller_id, p_match_character_id);
  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;

  select match_character_id into one_selection from public.battle_selections
    where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_one_id;
  select match_character_id into two_selection from public.battle_selections
    where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_two_id;
  if one_selection is null or two_selection is null then return; end if;

  select c.overall, c.power_score into one_overall, one_power
    from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = one_selection;
  select c.overall, c.power_score into two_overall, two_power
    from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = two_selection;
  round_winner := case
    when one_overall > two_overall then match_row.player_one_id
    when two_overall > one_overall then match_row.player_two_id
    when one_power > two_power then match_row.player_one_id
    when two_power > one_power then match_row.player_two_id
    else null
  end;
  next_one_score := match_row.player_one_score + case when round_winner = match_row.player_one_id then 1 else 0 end;
  next_two_score := match_row.player_two_score + case when round_winner = match_row.player_two_id then 1 else 0 end;

  update public.match_characters set used_in_battle = true where id in (one_selection, two_selection);
  insert into public.match_rounds (match_id, round_number, player_one_match_character_id, player_two_match_character_id, winner_player_id)
  values (p_match_id, match_row.current_battle_round, one_selection, two_selection, round_winner);
  delete from public.battle_selections where match_id = p_match_id and round_number = match_row.current_battle_round;

  if next_one_score >= 3 or next_two_score >= 3 or match_row.current_battle_round = 5 then
    final_winner := case when next_one_score > next_two_score then match_row.player_one_id when next_two_score > next_one_score then match_row.player_two_id else null end;
    update public.matches set status = 'completed', battle_state = 'complete', player_one_score = next_one_score,
      player_two_score = next_two_score, winner_id = final_winner, completed_at = now(),
      action_version = action_version + 1, updated_at = now() where id = p_match_id and status = 'battle';
    if final_winner is not null then
      update public.profiles set wins = wins + 1 where id = final_winner;
      update public.profiles set losses = losses + 1
        where id = case when final_winner = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
    end if;
  else
    update public.matches set battle_state = 'revealed', player_one_score = next_one_score,
      player_two_score = next_two_score, action_version = action_version + 1, updated_at = now() where id = p_match_id;
  end if;
end;
$$;

revoke all on function public.submit_battle_selection(uuid, uuid) from public;
grant execute on function public.submit_battle_selection(uuid, uuid) to authenticated;
notify pgrst, 'reload schema';
