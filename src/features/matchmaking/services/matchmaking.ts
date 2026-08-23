import { supabase } from '../../../lib/supabase'
import type { AdministratorMatchRpcRow, MatchmakingRpcRow, OnlineMatch, QueueEntry } from '../types'

function firstRpcRow(data: unknown): MatchmakingRpcRow | null {
  if (Array.isArray(data)) return (data[0] as MatchmakingRpcRow | undefined) ?? null
  return data as MatchmakingRpcRow | null
}

export async function findOrCreateMatch(): Promise<MatchmakingRpcRow> {
  const { data, error } = await supabase.rpc('find_or_create_match')
  if (error) throw error
  const result = firstRpcRow(data)
  if (!result) throw new Error('Matchmaking returned no result.')
  return result
}

export async function cancelMatchmaking(): Promise<MatchmakingRpcRow> {
  const { data, error } = await supabase.rpc('cancel_matchmaking')
  if (error) throw error
  const result = firstRpcRow(data)
  if (!result) throw new Error('Cancellation returned no result.')
  return result
}

export async function claimAdministratorMatch(): Promise<AdministratorMatchRpcRow> {
  const { data, error } = await supabase.rpc('claim_administrator_match')
  if (error) throw error
  const result = Array.isArray(data)
    ? (data[0] as AdministratorMatchRpcRow | undefined)
    : data as AdministratorMatchRpcRow | null
  if (!result) throw new Error('Administrator matchmaking returned no result.')
  return result
}

export async function matchHasSystemPlayer(matchId: string): Promise<boolean> {
  const { data: match, error: matchError } = await supabase
    .from('matches')
    .select('player_one_id, player_two_id')
    .eq('id', matchId)
    .single()
  if (matchError) throw matchError

  const { count, error: profileError } = await supabase
    .from('profiles')
    .select('id', { count: 'exact', head: true })
    .in('id', [match.player_one_id, match.player_two_id])
    .eq('is_system_player', true)
  if (profileError) throw profileError
  return (count ?? 0) > 0
}

export async function getActiveMatch(userId: string): Promise<OnlineMatch | null> {
  const { data, error } = await supabase
    .from('matches')
    .select('*')
    .or(`player_one_id.eq.${userId},player_two_id.eq.${userId}`)
    .not('status', 'in', '(completed,cancelled)')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data as OnlineMatch | null
}

export async function getOwnQueueEntry(userId: string): Promise<QueueEntry | null> {
  const { data, error } = await supabase
    .from('matchmaking_queue')
    .select('*')
    .eq('player_id', userId)
    .maybeSingle()
  if (error) throw error
  return data as QueueEntry | null
}
