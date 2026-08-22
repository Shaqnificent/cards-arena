-- Anime Arena: secure, explicit active-match cancellation and battle forfeiture.
-- Run after the current matchmaking and online battle migrations.

alter table public.matches
  add column if not exists forfeited_by uuid references public.profiles(id);

create or replace function public.cancel_active_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;
  if match_row.status = 'cancelled' then
    return jsonb_build_object('status', 'cancelled');
  end if;
  if match_row.status not in ('waiting', 'initiative', 'oc_selection', 'draft', 'oc_preparation') then
    raise exception 'Match can no longer be cancelled';
  end if;

  update public.matches set status = 'cancelled', winner_id = null, completed_at = now(),
    forfeited_by = null, action_version = action_version + 1, updated_at = now()
  where id = p_match_id;

  update public.matchmaking_queue set status = 'cancelled'
  where player_id in (match_row.player_one_id, match_row.player_two_id);

  return jsonb_build_object('status', 'cancelled');
end;
$$;

create or replace function public.forfeit_active_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  opponent_id uuid;
  match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;
  if match_row.status = 'completed' and match_row.forfeited_by = caller_id then
    return jsonb_build_object('status', 'completed', 'winnerId', match_row.winner_id, 'forfeitedBy', caller_id);
  end if;
  if match_row.status <> 'battle' then raise exception 'Match can no longer be forfeited'; end if;

  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  if opponent_id is null then raise exception 'Opponent unavailable'; end if;

  update public.matches set status = 'completed', winner_id = opponent_id, forfeited_by = caller_id,
    completed_at = now(), action_version = action_version + 1, updated_at = now()
  where id = p_match_id and status = 'battle';

  update public.profiles set wins = wins + 1 where id = opponent_id;
  update public.profiles set losses = losses + 1 where id = caller_id;
  update public.matchmaking_queue set status = 'cancelled'
  where player_id in (caller_id, opponent_id);

  return jsonb_build_object('status', 'completed', 'winnerId', opponent_id, 'forfeitedBy', caller_id);
end;
$$;

revoke all on function public.cancel_active_match(uuid) from public;
revoke all on function public.forfeit_active_match(uuid) from public;
grant execute on function public.cancel_active_match(uuid) to authenticated;
grant execute on function public.forfeit_active_match(uuid) to authenticated;

notify pgrst, 'reload schema';
