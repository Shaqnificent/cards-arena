import { supabase } from '../../../lib/supabase'
import type { ChallengeMutationResult, PlayerChallenge } from '../types'

export interface ChallengeLifecycle {
  status: PlayerChallenge['status']
  matchId: string | null
}

function rpcError(error: { message: string; code?: string } | null, fallback: string): never {
  if (error?.code === 'PGRST202') throw new Error('Direct Challenges are not installed yet. Run the latest challenge SQL migration.')
  throw new Error(error?.message || fallback)
}

export async function getPendingPlayerChallenge(): Promise<PlayerChallenge | null> {
  const { data, error } = await supabase.rpc('get_my_pending_player_challenge')
  if (error) rpcError(error, 'Unable to restore your pending challenge.')
  return data ? data as PlayerChallenge : null
}

export async function sendPlayerChallenge(challengedId: string): Promise<PlayerChallenge> {
  const { data, error } = await supabase.rpc('send_player_challenge', { p_challenged_id: challengedId })
  if (error) rpcError(error, 'Unable to send this challenge.')
  return data as PlayerChallenge
}

async function mutateChallenge(name: 'accept_player_challenge' | 'decline_player_challenge' | 'cancel_player_challenge', challengeId: string): Promise<ChallengeMutationResult> {
  const { data, error } = await supabase.rpc(name, { p_challenge_id: challengeId })
  if (error) rpcError(error, 'Unable to update this challenge.')
  return data as ChallengeMutationResult
}

export const acceptPlayerChallenge = (challengeId: string) => mutateChallenge('accept_player_challenge', challengeId)
export const declinePlayerChallenge = (challengeId: string) => mutateChallenge('decline_player_challenge', challengeId)
export const cancelPlayerChallenge = (challengeId: string) => mutateChallenge('cancel_player_challenge', challengeId)

export async function getChallengeLifecycle(challengeId: string): Promise<ChallengeLifecycle | null> {
  const { data, error } = await supabase.from('player_challenges').select('status,match_id').eq('id', challengeId).maybeSingle()
  if (error) throw error
  if (!data) return null
  const row = data as { status: PlayerChallenge['status']; match_id: string | null }
  return { status: row.status, matchId: row.match_id }
}
