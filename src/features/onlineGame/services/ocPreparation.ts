import { supabase } from '../../../lib/supabase'
import type { MatchOcPreparationState } from '../types'
import { loadMatchOcPortraits } from './matchOcPortraits'

function preserveAuthoritativeOcType(state: MatchOcPreparationState): MatchOcPreparationState {
  const ocType = state.yourOC?.ocType
  if (!state.yourOC || ocType === 'champion' || ocType === 'sacrificial') return state
  console.error('get_match_oc_preparation_state returned an unexpected ocType', {
    characterId: state.yourOC.characterId,
    ocType,
  })
  return { ...state, yourOC: { ...state.yourOC, ocType: null } }
}

export async function loadOcPreparation(matchId: string): Promise<MatchOcPreparationState> {
  const { data, error } = await supabase.rpc('get_match_oc_preparation_state', { p_match_id: matchId })
  if (error) throw error
  const state = preserveAuthoritativeOcType(data as MatchOcPreparationState)
  const portraits = await loadMatchOcPortraits(matchId)
  if (state.yourOC) state.yourOC.imageUrl = portraits.get(state.yourOC.characterId) ?? null
  return state
}

export async function submitOcPreparation(matchId: string, decision: 'reserve' | 'absorb' | 'inactive' | 'sacrifice', sacrificedId: string | null): Promise<MatchOcPreparationState> {
  const { data, error } = await supabase.rpc('submit_match_oc_preparation', {
    p_match_id: matchId, p_decision: decision, p_sacrificed_match_character_id: sacrificedId,
  })
  if (error) throw error
  return preserveAuthoritativeOcType(data as MatchOcPreparationState)
}
