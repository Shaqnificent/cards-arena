import { useEffect, useState } from 'react'
import { getPublicPlayerProfile } from '../services/publicPlayerProfile'
import type { PublicPlayerProfile } from '../types'

interface PublicPlayerProfileState {
  profile: PublicPlayerProfile | null
  loading: boolean
  unavailable: boolean
}

interface LoadedPublicPlayerProfileState extends PublicPlayerProfileState {
  playerId: string | null
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function usePublicPlayerProfile(playerId: string | undefined): PublicPlayerProfileState {
  const [state, setState] = useState<LoadedPublicPlayerProfileState>({
    playerId: null,
    profile: null,
    loading: true,
    unavailable: false,
  })

  useEffect(() => {
    let isCurrent = true

    if (!playerId || !uuidPattern.test(playerId)) return () => { isCurrent = false }

    void getPublicPlayerProfile(playerId)
      .then((profile) => {
        if (isCurrent) setState({ playerId, profile, loading: false, unavailable: profile === null })
      })
      .catch((error: unknown) => {
        console.error('Public player profile load failed', error)
        if (isCurrent) setState({ playerId, profile: null, loading: false, unavailable: true })
      })

    return () => { isCurrent = false }
  }, [playerId])

  if (!playerId || !uuidPattern.test(playerId)) return { profile: null, loading: false, unavailable: true }
  if (state.playerId !== playerId) return { profile: null, loading: true, unavailable: false }
  return state
}
