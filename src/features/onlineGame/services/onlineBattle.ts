import { supabase } from '../../../lib/supabase'
import type { OnlineBattleState } from '../battleTypes'

export async function initializeOnlineBattle(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('initialize_online_battle', { p_match_id: matchId })
  if (error) throw error
}

export async function loadOnlineBattle(matchId: string): Promise<OnlineBattleState> {
  const { data, error } = await supabase.rpc('get_online_battle_state', { p_match_id: matchId })
  if (error) throw error
  if (!data || typeof data !== 'object') throw new Error('Battle state unavailable')
  return data as OnlineBattleState
}

export async function lockBattleFighter(matchId: string, selectionType: 'canon' | 'oc', fighterId: string): Promise<void> {
  const { error } = await supabase.rpc('submit_battle_selection', {
    p_match_id: matchId,
    p_selection_type: selectionType,
    p_fighter_id: fighterId,
  })
  if (error) throw error
}

export async function advanceOnlineBattle(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('advance_battle_round', { p_match_id: matchId })
  if (error) throw error
}
