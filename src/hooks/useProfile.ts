import { useCallback, useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Profile } from '../types/profile'
import type { ProfileIdentityUpdate } from '../features/profile/avatarIdentity'

interface ProfileState {
  profile: Profile | null
  loading: boolean
  error: string | null
  refresh: () => Promise<void>
  applyIdentity: (identity: ProfileIdentityUpdate) => void
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

  const loadProfile = useCallback(async () => {
    if (!userId) return
    const { data, error } = await supabase.rpc('get_my_profile')
    const profile = data && typeof data === 'object' ? data as Profile : null
    setState({
      userId,
      profile,
      error: error?.message ?? (profile ? null : 'Player profile was not found.'),
    })
  }, [userId])

  const applyIdentity = useCallback((identity: ProfileIdentityUpdate) => {
    setState((current) => current.userId !== userId || !current.profile ? current : ({
      ...current,
      profile: {
        ...current.profile,
        username: identity.username,
        username_changes_remaining: identity.usernameChangesRemaining,
        avatar_url: identity.avatarUrl,
        avatar_mode: identity.avatarMode,
        avatar_bg_color: identity.avatarBgColor,
        avatar_text_color: identity.avatarTextColor,
      },
    }))
  }, [userId])

  useEffect(() => {
    if (!userId) {
      return
    }

    void Promise.resolve().then(loadProfile)
  }, [loadProfile, userId])

  if (!userId) {
    return { profile: null, loading: false, error: null, refresh: loadProfile, applyIdentity }
  }

  if (state.userId !== userId) {
    return { profile: null, loading: true, error: null, refresh: loadProfile, applyIdentity }
  }

  return { profile: state.profile, loading: false, error: state.error, refresh: loadProfile, applyIdentity }
}
