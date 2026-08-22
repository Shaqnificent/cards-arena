import { supabase } from '../../../lib/supabase'
import type { MatchmakingRpcRow, OnlineMatch, QueueEntry } from '../types'

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
