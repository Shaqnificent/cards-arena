import { supabase } from '../../../lib/supabase'
import type { BoonDashboard, BoonDefinition, BoonRollResolution, BoonRollResult } from '../types'

function requireObject<T>(value: unknown, message: string): T {
  if (!value || typeof value !== 'object') throw new Error(message)
  return value as T
}

export async function getBoonDashboard(): Promise<BoonDashboard> {
  const { data, error } = await supabase.rpc('get_my_boons')
  if (error) throw error
  return requireObject<BoonDashboard>(data, 'Boon inventory is unavailable.')
}

export async function getBoonCatalogue(): Promise<BoonDefinition[]> {
  const { data, error } = await supabase.rpc('get_boon_catalogue')
  if (error) throw error
  return Array.isArray(data) ? data as BoonDefinition[] : []
}

export async function equipOwnedBoon(playerBoonId: string): Promise<BoonDashboard> {
  const { data, error } = await supabase.rpc('equip_boon', { p_player_boon_id: playerBoonId })
  if (error) throw error
  return requireObject<BoonDashboard>(data, 'The equipped Boon state was not returned.')
}

export async function unequipOwnedBoon(): Promise<BoonDashboard> {
  const { data, error } = await supabase.rpc('unequip_boon')
  if (error) throw error
  return requireObject<BoonDashboard>(data, 'The Boon inventory state was not returned.')
}

export async function rollBoon(): Promise<BoonRollResult> {
  const { data, error } = await supabase.rpc('roll_boon')
  if (error) throw error
  return requireObject<BoonRollResult>(data, 'The Boon roll result was not returned.')
}

export async function resolveBoonRoll(
  rollId: string,
  action: 'replace' | 'discard',
  replacePlayerBoonId: string | null = null,
): Promise<BoonRollResolution> {
  const { data, error } = await supabase.rpc('resolve_boon_roll', {
    p_roll_id: rollId,
    p_action: action,
    p_replace_player_boon_id: replacePlayerBoonId,
  })
  if (error) throw error
  return requireObject<BoonRollResolution>(data, 'The resolved Boon state was not returned.')
}
