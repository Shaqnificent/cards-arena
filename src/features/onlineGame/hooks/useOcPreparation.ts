import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabase'
import { loadOcPreparation, submitOcPreparation } from '../services/ocPreparation'
import { wakeAdministratorOpponent } from '../services/onlineDraft'
import type { MatchOcPreparationState } from '../types'

export function useOcPreparation(matchId: string) {
  const [state, setState] = useState<MatchOcPreparationState | null>(null)
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const refresh = useCallback(async () => {
    try { await wakeAdministratorOpponent(matchId); setState(await loadOcPreparation(matchId)); setError(null) }
    catch (cause) { console.error('OC preparation load failed', cause); setError('Unable to load OC preparation.') }
    finally { setLoading(false) }
  }, [matchId])
  useEffect(() => {
    void Promise.resolve().then(refresh)
    const channel = supabase.channel(`oc-preparation:${matchId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void refresh() })
      .subscribe()
    return () => { void supabase.removeChannel(channel) }
  }, [matchId, refresh])
  const lock = async (decision: 'reserve' | 'absorb' | 'inactive' | 'sacrifice', sacrificedId: string | null) => {
    if (pending) return
    setPending(true); setError(null)
    try { setState(await submitOcPreparation(matchId, decision, sacrificedId)) }
    catch (cause) { console.error('OC preparation rejected', cause); setError('That preparation could not be locked. Your current state was restored.'); await refresh() }
    finally { setPending(false) }
  }
  return { state, loading, pending, error, lock, retry: refresh }
}
