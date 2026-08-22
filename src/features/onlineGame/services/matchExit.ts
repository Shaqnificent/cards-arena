import { supabase } from '../../../lib/supabase'
import type { MatchStatus } from '../../matchmaking/types'

export interface MatchExitState {
  status: MatchStatus
  winner_id: string | null
  forfeited_by: string | null
}

export async function loadMatchExitState(matchId: string): Promise<MatchExitState> {
  const detailed = await supabase.from('matches').select('status,winner_id,forfeited_by').eq('id', matchId).single()
  if (!detailed.error) return detailed.data as MatchExitState

  // Keep the leave control available while a newly installed column is still
  // absent from PostgREST's schema cache. The RPC remains authoritative.
  const fallback = await supabase.from('matches').select('status,winner_id').eq('id', matchId).single()
  if (fallback.error) throw fallback.error
  return { ...(fallback.data as Omit<MatchExitState, 'forfeited_by'>), forfeited_by: null }
}

export async function cancelActiveMatch(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('cancel_active_match', { p_match_id: matchId })
  if (error) throw error
}

export async function forfeitActiveMatch(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('forfeit_active_match', { p_match_id: matchId })
  if (error) throw error
}
