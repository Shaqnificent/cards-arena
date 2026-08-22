import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../../lib/supabase'
import {
  initializeOnlineDraft, loadOnlineDraft, submitDraftBid, submitDraftFold, submitDraftPass, validateMatchParticipant,
} from '../services/onlineDraft'
import type { OnlineDraftAction, OnlineDraftState, OnlineMatchLoadState } from '../types'

function setupError(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'PGRST202') {
    return 'Online draft setup is incomplete. Run docs/supabase_online_draft.sql in Supabase.'
  }
  return 'Unable to prepare the online draft.'
}

export function useOnlineDraft(matchId: string, currentUserId: string) {
  const [state, setState] = useState<OnlineDraftState | null>(null)
  const [loadState, setLoadState] = useState<OnlineMatchLoadState>('loading-match')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [pendingAction, setPendingAction] = useState<OnlineDraftAction>(null)
  const requestVersion = useRef(0)
  const initializationPromise = useRef<Promise<void> | null>(null)

  const fetchAuthoritativeState = useCallback(async (showLoading = false) => {
    const request = ++requestVersion.current
    if (showLoading) setLoadState('loading-draft')
    try {
      const nextState = await loadOnlineDraft(matchId, currentUserId)
      if (request === requestVersion.current) {
        setState(nextState)
        setError(null)
        setLoadState('ready')
      }
    } catch (loadError) {
      if (request === requestVersion.current) {
        console.error('Online draft state load failed', loadError)
        setError(setupError(loadError))
        setLoadState('error')
      }
    }
  }, [currentUserId, matchId])

  const prepare = useCallback(async (force = false) => {
    const request = ++requestVersion.current

    try {
      const { data: { session }, error: sessionError } = await supabase.auth.getSession()
      if (request !== requestVersion.current) return
      setError(null)
      setMessage(null)
      setLoadState('loading-match')
      if (sessionError || session?.user.id !== currentUserId) throw sessionError ?? new Error('Authentication required')
      await validateMatchParticipant(matchId, currentUserId)
      if (request !== requestVersion.current) return

      setLoadState('initializing-draft')
      if (force) initializationPromise.current = null
      initializationPromise.current ??= initializeOnlineDraft(matchId)
      await initializationPromise.current
      if (request !== requestVersion.current) return

      setLoadState('loading-draft')
      const nextState = await loadOnlineDraft(matchId, currentUserId)
      if (request !== requestVersion.current) return
      setState(nextState)
      setError(null)
      setLoadState('ready')
    } catch (prepareError) {
      if (request !== requestVersion.current) return
      console.error('Online draft preparation failed', prepareError)
      initializationPromise.current = null
      setError(setupError(prepareError))
      setLoadState('error')
    }
  }, [currentUserId, matchId])

  useEffect(() => {
    // Start after the effect setup completes; the request generation guard
    // cancels the superseded Strict Mode chain without delaying initialization.
    void Promise.resolve().then(() => prepare())
    return () => { requestVersion.current += 1 }
  }, [prepare])

  useEffect(() => {
    if (loadState !== 'ready') return
    const notify = () => { void fetchAuthoritativeState() }
    const channel = supabase.channel(`online-draft:${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, notify)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_players', filter: `match_id=eq.${matchId}` }, notify)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_characters', filter: `match_id=eq.${matchId}` }, notify)
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          setMessage('Live connection interrupted. Refreshing still restores the authoritative draft.')
        }
      })
    return () => { void supabase.removeChannel(channel) }
  }, [fetchAuthoritativeState, loadState, matchId])

  const runAction = useCallback(async (action: Exclude<OnlineDraftAction, null>, operation: () => Promise<void>) => {
    if (pendingAction) return
    setPendingAction(action)
    setMessage(null)
    try {
      await operation()
    } catch {
      setMessage('That action was not accepted. The latest game state has been restored.')
    } finally {
      await fetchAuthoritativeState()
      setPendingAction(null)
    }
  }, [fetchAuthoritativeState, pendingAction])

  return {
    state, loadState, loading: loadState !== 'ready' && loadState !== 'error', error, message, pendingAction,
    bid: (amount: number) => runAction('bid', () => submitDraftBid(matchId, amount)),
    pass: () => runAction('pass', () => submitDraftPass(matchId)),
    fold: () => runAction('fold', () => submitDraftFold(matchId)),
    retry: () => prepare(true),
  }
}
