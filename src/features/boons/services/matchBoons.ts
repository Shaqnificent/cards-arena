import { supabase } from '../../../lib/supabase'
import type { ActiveMatchBoonState } from '../../onlineGame/types'

export async function getMyActiveMatchBoon(): Promise<ActiveMatchBoonState | null> {
  const { data, error } = await supabase.rpc('get_my_active_match_boon')
  if (error) throw error
  return data as ActiveMatchBoonState | null
}
