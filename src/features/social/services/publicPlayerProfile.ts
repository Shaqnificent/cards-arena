import { supabase } from '../../../lib/supabase'
import type { PublicPlayerProfile } from '../types'

export async function getPublicPlayerProfile(playerId: string): Promise<PublicPlayerProfile | null> {
  const { data, error } = await supabase.rpc('get_public_player_profile', {
    p_player_id: playerId,
  })
  if (error) throw error
  return data as PublicPlayerProfile | null
}
