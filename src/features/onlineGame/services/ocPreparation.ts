import { supabase } from '../../../lib/supabase'
import type { MatchOcPreparationState } from '../types'

export async function loadOcPreparation(matchId: string): Promise<MatchOcPreparationState> {
  const { data, error } = await supabase.rpc('get_match_oc_preparation_state', { p_match_id: matchId })
  if (error) throw error
  return data as MatchOcPreparationState
}

export async function submitOcPreparation(matchId: string, decision: 'reserve' | 'sacrifice', sacrificedId: string | null): Promise<MatchOcPreparationState> {
  const { data, error } = await supabase.rpc('submit_match_oc_preparation', {
    p_match_id: matchId, p_decision: decision, p_sacrificed_match_character_id: sacrificedId,
  })
  if (error) throw error
  return data as MatchOcPreparationState
}
