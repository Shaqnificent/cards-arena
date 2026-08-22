import { supabase } from '../../../lib/supabase'

interface MatchOcPortrait { characterId: string; imageUrl: string | null }

export async function loadMatchOcPortraits(matchId: string): Promise<Map<string, string | null>> {
  const { data, error } = await supabase.rpc('get_match_oc_portraits', { p_match_id: matchId })
  if (error) throw error
  return new Map(((data ?? []) as MatchOcPortrait[]).map((portrait) => [portrait.characterId, portrait.imageUrl]))
}
