import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Verse } from '../types/verse'

interface VersesState {
  verses: Verse[]
  loading: boolean
  error: string | null
}

export function useVerses(): VersesState {
  const [state, setState] = useState<VersesState>({ verses: [], loading: true, error: null })

  useEffect(() => {
    let isCurrent = true

    const loadVerses = async () => {
      const { data, error } = await supabase
        .from('verses')
        .select('id, name, slug, image_url, active')
        .eq('active', true)
        .order('name')

      if (!isCurrent) return
      setState({
        verses: (data ?? []) as Verse[],
        loading: false,
        error: error?.message ?? null,
      })
    }

    void loadVerses()
    return () => { isCurrent = false }
  }, [])

  return state
}
