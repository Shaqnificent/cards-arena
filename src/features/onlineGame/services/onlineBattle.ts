import { supabase } from '../../../lib/supabase'
import type { OnlineBattleState } from '../battleTypes'
import { loadMatchOcPortraits } from './matchOcPortraits'
import { withSystemIdentity } from './systemIdentity'

export async function initializeOnlineBattle(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('initialize_online_battle', { p_match_id: matchId })
  if (error) throw error
}

export async function loadOnlineBattle(matchId: string): Promise<OnlineBattleState> {
  const [{ data, error }, preparationResult, boonResult] = await Promise.all([
    supabase.rpc('get_online_battle_state', { p_match_id: matchId }),
    supabase.rpc('get_match_oc_preparation_state', { p_match_id: matchId }),
    supabase.rpc('get_my_match_boon_result', { p_match_id: matchId }),
  ])
  if (error) throw error
  if (!data || typeof data !== 'object') throw new Error('Battle state unavailable')
  const state = data as OnlineBattleState
  const boon = !boonResult.error && boonResult.data && typeof boonResult.data === 'object'
    ? boonResult.data as { boonPointsEarned?: number; boonPointBalance?: number }
    : null
  if (boonResult.error) {
    console.error('Match Boon reward load failed', {
      matchId,
      code: boonResult.error.code,
      message: boonResult.error.message,
      details: boonResult.error.details,
      hint: boonResult.error.hint,
    })
  }
  state.boonPointsEarned = boon?.boonPointsEarned ?? 0
  state.boonPointBalance = boon?.boonPointBalance ?? 0
  if (!preparationResult.error && preparationResult.data && typeof preparationResult.data === 'object') {
    const preparation = preparationResult.data as {
      yourPreparation?: {
        ocType?: 'champion' | 'sacrificial' | null
        decision?: 'reserve' | 'absorb' | 'inactive' | 'sacrifice'
        sacrificedMatchCharacterId?: string | null
      } | null
    }
    const ownPreparation = preparation.yourPreparation
    if (ownPreparation?.sacrificedMatchCharacterId) {
      state.yourTeam = state.yourTeam.map((fighter) => ({
        ...fighter,
        sacrificed: fighter.id === ownPreparation.sacrificedMatchCharacterId || fighter.sacrificed,
      }))
    }
    if (state.yourOC && ownPreparation?.ocType &&
      (ownPreparation.decision === 'reserve' ||
        (ownPreparation.ocType === 'champion' && ownPreparation.decision === 'absorb'))) {
      state.yourOC.ocType = ownPreparation.ocType
      state.yourOC.decision = ownPreparation.decision
      state.yourSupport = null
    } else if (state.yourOC && ownPreparation?.ocType === 'sacrificial' &&
      (ownPreparation.decision === 'inactive' || ownPreparation.decision === 'sacrifice')) {
      state.yourSupport = {
        ...state.yourOC,
        ocType: 'sacrificial',
        decision: ownPreparation.decision,
      }
      state.yourOC = null
    }
  }
  const portraits = await loadMatchOcPortraits(matchId)
  if (state.yourOC) state.yourOC.imageUrl = portraits.get(state.yourOC.id) ?? null
  if (state.opponentOC) state.opponentOC.imageUrl = portraits.get(state.opponentOC.id) ?? null
  if (state.yourSupport) state.yourSupport.imageUrl = portraits.get(state.yourSupport.id) ?? null
  if (state.opponentSupport) state.opponentSupport.imageUrl = portraits.get(state.opponentSupport.id) ?? null
  return withSystemIdentity(state)
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
