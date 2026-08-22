import { supabase } from '../../../lib/supabase'
import type { LocalProgressionResult, OcProgressionReward, PlayerCharacter } from '../types'

export async function getUnclaimedProgressionRewards(): Promise<OcProgressionReward[]> {
  const { data, error } = await supabase
    .from('oc_progression_rewards')
    .select('id, owner_id, source_match_id, points, claimed_character_id, claimed_at, created_at')
    .is('claimed_at', null)
    .order('created_at')
  if (error) throw error
  return (data ?? []) as OcProgressionReward[]
}

export async function startLocalProgressionMatch(): Promise<string> {
  const { data, error } = await supabase.rpc('start_local_progression_match')
  if (error) throw error
  return data as string
}

export async function completeLocalProgressionMatch(matchId: string, playerScore: number, opponentScore: number, roundCount: number): Promise<LocalProgressionResult> {
  const { data, error } = await supabase.rpc('complete_local_progression_match', {
    p_match_id: matchId,
    p_player_score: playerScore,
    p_opponent_score: opponentScore,
    p_round_count: roundCount,
  }).single()
  if (error) throw error
  return data as LocalProgressionResult
}

export async function claimProgressionReward(rewardId: string, characterId: string): Promise<PlayerCharacter> {
  const { data, error } = await supabase.rpc('claim_oc_progression_reward', {
    p_reward_id: rewardId,
    p_character_id: characterId,
  })
  if (error) throw error
  return data as PlayerCharacter
}

export async function upgradeOverall(characterId: string): Promise<PlayerCharacter> {
  const { data, error } = await supabase.rpc('upgrade_player_character_overall', { p_character_id: characterId })
  if (error) throw error
  return data as PlayerCharacter
}

export async function upgradePower(characterId: string): Promise<PlayerCharacter> {
  const { data, error } = await supabase.rpc('upgrade_player_character_power', { p_character_id: characterId })
  if (error) throw error
  return data as PlayerCharacter
}
