import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Character } from '../types/character'

interface CharactersState {
  characters: Character[]
  loading: boolean
  error: string | null
}

export function useCharacters(): CharactersState {
  
  const [state, setState] = useState<CharactersState>({
    characters: [],
    loading: true,
    error: null,
  })

  useEffect(() => {
    let isCurrent = true

    const loadCharacters = async () => {
      const { data, error } = await supabase
        .from('characters')
        .select(`
          id,
          name,
          slug,
          version,
          image_url,
          overall,
          power_score,
          active,
          verse_id,
          verses (id, name, slug)
        `)
        .eq('active', true)
        .order('overall', { ascending: false })
        .order('name', { ascending: true })

      if (!isCurrent) return

      setState({
        characters: (data ?? []) as unknown as Character[],
        loading: false,
        error: error?.message ?? null,
      })
    }

    void loadCharacters()
    return () => { isCurrent = false }
  }, [])

  return state
}
