import { useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Profile } from '../types/profile'

interface ProfileState {
  profile: Profile | null
  loading: boolean
  error: string | null
}

interface StoredProfileState {
  userId: string | null
  profile: Profile | null
  error: string | null
}

export function useProfile(user: User | null): ProfileState {
  const [state, setState] = useState<StoredProfileState>({
    userId: null,
    profile: null,
    error: null,
  })
  const userId = user?.id ?? null

  useEffect(() => {
    let isCurrent = true

    if (!userId) {
      return
    }

    const loadProfile = async () => {
      const { data, error } = await supabase.rpc('get_my_profile')
      const profile = data && typeof data === 'object' ? data as Profile : null

      if (!isCurrent) return

      setState({
        userId,
        profile,
        error: error?.message ?? (profile ? null : 'Player profile was not found.'),
      })
    }

    void loadProfile()

    return () => {
      isCurrent = false
    }
  }, [userId])

  if (!userId) {
    return { profile: null, loading: false, error: null }
  }

  if (state.userId !== userId) {
    return { profile: null, loading: true, error: null }
  }

  return { profile: state.profile, loading: false, error: state.error }
}
