import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../../lib/supabase'
import type { OnlineBattleAction, OnlineBattleState } from '../battleTypes'
import { advanceOnlineBattle, initializeOnlineBattle, loadOnlineBattle, lockBattleFighter } from '../services/onlineBattle'

export function useOnlineBattle(matchId: string) {
  const [state, setState] = useState<OnlineBattleState | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [pendingAction, setPendingAction] = useState<OnlineBattleAction>(null)
  const requestVersion = useRef(0)

  const refresh = useCallback(async () => {
    const request = ++requestVersion.current
    try {
      const nextState = await loadOnlineBattle(matchId)
      if (request === requestVersion.current) {
        setState(nextState)
        setError(null)
        setLoading(false)
      }
    } catch (loadError) {
      if (request === requestVersion.current) {
        console.error('Online battle state load failed', loadError)
        setError('Unable to load the online battle.')
        setLoading(false)
      }
    }
  }, [matchId])

  const prepare = useCallback(async () => {
    const request = ++requestVersion.current
    setLoading(true)
    setError(null)
    try {
      await initializeOnlineBattle(matchId)
      if (request !== requestVersion.current) return
      const nextState = await loadOnlineBattle(matchId)
      if (request !== requestVersion.current) return
      setState(nextState)
      setLoading(false)
    } catch (prepareError) {
      if (request !== requestVersion.current) return
      console.error('Online battle preparation failed', prepareError)
      setError('Unable to prepare the online battle. Run docs/supabase_online_battle.sql if it is not installed.')
      setLoading(false)
    }
  }, [matchId])

  useEffect(() => {
    void Promise.resolve().then(prepare)
    return () => { requestVersion.current += 1 }
  }, [prepare])

  useEffect(() => {
    if (!state) return
    const channel = supabase.channel(`online-battle:${matchId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void refresh() })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') setMessage('Live connection interrupted. Retry restores the authoritative battle.')
      })
    return () => { void supabase.removeChannel(channel) }
  }, [matchId, refresh, state])

  const runAction = useCallback(async (action: Exclude<OnlineBattleAction, null>, operation: () => Promise<void>) => {
    if (pendingAction) return
    setPendingAction(action)
    setMessage(null)
    try {
      await operation()
    } catch (actionError) {
      console.error('Online battle action rejected', actionError)
      setMessage('That action was not accepted. The latest battle state has been restored.')
    } finally {
      await refresh()
      setPendingAction(null)
    }
  }, [pendingAction, refresh])

  return {
    state, loading, error, message, pendingAction,
    lock: (selectionType: 'canon' | 'oc', fighterId: string) => runAction('lock', () => lockBattleFighter(matchId, selectionType, fighterId)),
    advance: () => runAction('advance', () => advanceOnlineBattle(matchId)),
    retry: prepare,
  }
}
