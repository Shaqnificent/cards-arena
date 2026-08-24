import { useCallback, useEffect, useState } from 'react'
import type { ActiveMatchBoonState } from '../../onlineGame/types'
import { getMyActiveMatchBoon } from '../services/matchBoons'

export function useActiveMatchBoon(enabled: boolean) {
  const [activeMatch, setActiveMatch] = useState<ActiveMatchBoonState | null>(null)
  const [loading, setLoading] = useState(enabled)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (!enabled) {
      setActiveMatch(null)
      setLoading(false)
      return
    }
    setLoading(true)
    try {
      setActiveMatch(await getMyActiveMatchBoon())
      setError(null)
    } catch (cause) {
      console.error('Active match Boon snapshot load failed', cause)
      setError('Unable to load the Boon locked for your active match.')
    } finally {
      setLoading(false)
    }
  }, [enabled])

  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  return { activeMatch, loading, error, refresh }
}
