import { useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabase'

export type MatchSource = 'matchmaking' | 'direct_challenge' | 'administrator'

export function useMatchSource(matchId: string): MatchSource {
  const [source, setSource] = useState<MatchSource>('matchmaking')
  useEffect(() => {
    let current = true
    void supabase.from('matches').select('match_source').eq('id', matchId).single().then(({ data, error }) => {
      if (!current || error) return
      const value = (data as { match_source?: string } | null)?.match_source
      if (value === 'direct_challenge' || value === 'administrator' || value === 'matchmaking') setSource(value)
    })
    return () => { current = false }
  }, [matchId])
  return source
}
