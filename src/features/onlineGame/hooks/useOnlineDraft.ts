import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../../lib/supabase'
import {
  advanceInitiativeRound, initializeMatchInitiative, initializeMatchOcSelection, initializeOnlineDraft, loadMatchInitiative, loadMatchOcSelection, loadOnlineDraft, submitDraftBid, submitDraftFold, submitDraftPass, submitInitiativeChoice, submitMatchOcSelection, validateMatchParticipant, wakeAdministratorOpponent,
} from '../services/onlineDraft'
import type { InitiativeChoice, MatchOcSelectionState, OnlineDraftAction, OnlineDraftState, OnlineInitiativeState, OnlineMatchLoadState } from '../types'

function setupError(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'PGRST202') {
    return 'Online match setup is incomplete. Run the latest online draft and OC-selection SQL files in Supabase.'
  }
  return 'Unable to prepare the online draft.'
}

export function useOnlineDraft(matchId: string, currentUserId: string) {
  const [state, setState] = useState<OnlineDraftState | null>(null)
  const [initiative, setInitiative] = useState<OnlineInitiativeState | null>(null)
  const [ocSelection, setOcSelection] = useState<MatchOcSelectionState | null>(null)
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
      const status = await validateMatchParticipant(matchId, currentUserId)
      if (request !== requestVersion.current) return
      await wakeAdministratorOpponent(matchId)
      if (request !== requestVersion.current) return

      if (status === 'waiting' || status === 'initiative') {
        setLoadState('determining-initiative')
        await initializeMatchInitiative(matchId)
        if (request !== requestVersion.current) return
        const initiativeState = await loadMatchInitiative(matchId, currentUserId)
        if (request !== requestVersion.current) return
        setInitiative(initiativeState)
        setLoadState('initiative')
        return
      }

      if (status === 'oc_selection') {
        setOcSelection(await loadMatchOcSelection(matchId, currentUserId))
        if (request !== requestVersion.current) return
        setLoadState('oc-selection')
        return
      }

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
    if (loadState !== 'initiative' || initiative?.initiativeState !== 'revealed') return
    const timer = window.setTimeout(() => {
      const startDraft = async () => {
        const request = ++requestVersion.current
        try {
          if (initiative.isDraw) {
            await advanceInitiativeRound(matchId)
            if (request !== requestVersion.current) return
            const nextInitiative = await loadMatchInitiative(matchId, currentUserId)
            if (request !== requestVersion.current) return
            setInitiative(nextInitiative)
            return
          }
          setLoadState('initializing-oc-selection')
          const nextOcSelection = await initializeMatchOcSelection(matchId)
          if (request !== requestVersion.current) return
          if (nextOcSelection.status === 'oc_selection') {
            setOcSelection(nextOcSelection)
            setInitiative(null)
            setLoadState('oc-selection')
            return
          }
          setLoadState('loading-draft')
          const nextState = await loadOnlineDraft(matchId, currentUserId)
          if (request !== requestVersion.current) return
          setState(nextState)
          setInitiative(null)
          setLoadState('ready')
        } catch (draftError) {
          if (request !== requestVersion.current) return
          console.error('OC selection start after initiative failed', draftError)
          setError(setupError(draftError))
          setLoadState('error')
        }
      }
      void startDraft()
    }, 2200)
    return () => window.clearTimeout(timer)
  }, [currentUserId, initiative, loadState, matchId])

  useEffect(() => {
    if (loadState !== 'oc-selection') return
    const refreshOcSelection = async () => {
      try {
        const next = await loadMatchOcSelection(matchId, currentUserId)
        if (next.status === 'draft') {
          setLoadState('loading-draft')
          setState(await loadOnlineDraft(matchId, currentUserId))
          setOcSelection(null)
          setLoadState('ready')
        } else setOcSelection(next)
      } catch (selectionError) { console.error('OC selection state refresh failed', selectionError) }
    }
    const channel = supabase.channel(`match-oc-selection:${matchId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void refreshOcSelection() })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') setMessage('Live OC selection connection interrupted. Refreshing restores the authoritative state.')
      })
    return () => { void supabase.removeChannel(channel) }
  }, [currentUserId, loadState, matchId])

  useEffect(() => {
    if (loadState !== 'initiative') return
    const refreshInitiative = async () => {
      try { setInitiative(await loadMatchInitiative(matchId, currentUserId)) }
      catch (initiativeError) { console.error('Initiative state refresh failed', initiativeError) }
    }
    const channel = supabase.channel(`match-initiative:${matchId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void refreshInitiative() })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') setMessage('Live initiative connection interrupted. Refreshing restores the authoritative state.')
      })
    return () => { void supabase.removeChannel(channel) }
  }, [currentUserId, loadState, matchId])

  const lockInitiative = useCallback(async (choice: InitiativeChoice) => {
    try {
      setMessage(null)
      await submitInitiativeChoice(matchId, choice)
      setInitiative(await loadMatchInitiative(matchId, currentUserId))
    } catch (choiceError) {
      console.error('Initiative choice rejected', choiceError)
      setMessage('That initiative choice was not accepted. The latest state has been restored.')
      try { setInitiative(await loadMatchInitiative(matchId, currentUserId)) } catch { /* Retry remains available through refresh. */ }
    }
  }, [currentUserId, matchId])

  const lockOcSelection = useCallback(async (characterId: string) => {
    if (pendingAction) return
    setPendingAction('oc-lock')
    setMessage(null)
    try {
      const next = await submitMatchOcSelection(matchId, characterId)
      if (next.status === 'draft') {
        setLoadState('loading-draft')
        setState(await loadOnlineDraft(matchId, currentUserId))
        setOcSelection(null)
        setLoadState('ready')
      } else setOcSelection(next)
    } catch (selectionError) {
      console.error('OC selection rejected', selectionError)
      setMessage('That OC selection was not accepted. The latest state has been restored.')
      try { setOcSelection(await loadMatchOcSelection(matchId, currentUserId)) } catch { /* Refresh remains available. */ }
    } finally { setPendingAction(null) }
  }, [currentUserId, matchId, pendingAction])

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
    state, initiative, ocSelection, loadState, loading: loadState !== 'ready' && loadState !== 'initiative' && loadState !== 'oc-selection' && loadState !== 'error', error, message, pendingAction,
    lockInitiative, lockOcSelection,
    bid: (amount: number) => runAction('bid', () => submitDraftBid(matchId, amount)),
    pass: () => runAction('pass', () => submitDraftPass(matchId)),
    fold: () => runAction('fold', () => submitDraftFold(matchId)),
    retry: () => prepare(true),
  }
}
