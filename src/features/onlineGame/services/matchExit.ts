import { supabase } from '../../../lib/supabase'
import type { MatchStatus } from '../../matchmaking/types'

export interface MatchExitState {
  status: MatchStatus
  match_source: 'matchmaking' | 'direct_challenge' | 'administrator'
  winner_id: string | null
  forfeited_by: string | null
  boon_points_earned: number
  boon_point_balance: number
}

export async function loadMatchExitState(matchId: string): Promise<MatchExitState> {
  const [detailed, boon] = await Promise.all([
    supabase.from('matches').select('status,winner_id,forfeited_by,match_source').eq('id', matchId).single(),
    supabase.rpc('get_my_match_boon_result', { p_match_id: matchId }),
  ])
  const reward = !boon.error && boon.data && typeof boon.data === 'object'
    ? boon.data as { boonPointsEarned?: number; boonPointBalance?: number }
    : null
  if (!detailed.error) return {
    ...(detailed.data as Omit<MatchExitState, 'boon_points_earned' | 'boon_point_balance'>),
    boon_points_earned: reward?.boonPointsEarned ?? 0,
    boon_point_balance: reward?.boonPointBalance ?? 0,
  }

  // Keep the leave control available while a newly installed column is still
  // absent from PostgREST's schema cache. The RPC remains authoritative.
  const fallback = await supabase.from('matches').select('status,winner_id').eq('id', matchId).single()
  if (fallback.error) throw fallback.error
  return {
    ...(fallback.data as Omit<MatchExitState, 'match_source' | 'forfeited_by' | 'boon_points_earned' | 'boon_point_balance'>),
    match_source: 'matchmaking',
    forfeited_by: null,
    boon_points_earned: reward?.boonPointsEarned ?? 0,
    boon_point_balance: reward?.boonPointBalance ?? 0,
  }
}

export async function cancelActiveMatch(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('cancel_active_match', { p_match_id: matchId })
  if (error) throw error
}

export async function forfeitActiveMatch(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('forfeit_active_match', { p_match_id: matchId })
  if (error) throw error
}
