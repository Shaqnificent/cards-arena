import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../../lib/supabase'
import { ADMINISTRATOR_MATCH_TIMEOUT_SECONDS } from '../config'
import {
  cancelMatchmaking,
  claimAdministratorMatch,
  findOrCreateMatch,
  getActiveMatch,
  getOwnQueueEntry,
  matchHasSystemPlayer,
} from '../services/matchmaking'
import type { MatchmakingController, MatchmakingState, QueueEntry } from '../types'

function matchmakingErrorMessage(error: unknown, fallback: string): string {
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'PGRST202') {
    return 'Matchmaking setup is incomplete. Run the latest Supabase matchmaking migrations.'
  }
  return fallback
}

export function useMatchmaking(userId: string): MatchmakingController {
  const navigate = useNavigate()
  const [status, setStatus] = useState<MatchmakingState>('checking')
  const [error, setError] = useState<string | null>(null)
  const [queueJoinedAt, setQueueJoinedAt] = useState<string | null>(null)
  const [claimingAdministrator, setClaimingAdministrator] = useState(false)
  const [administratorMatched, setAdministratorMatched] = useState(false)
  const claimInFlight = useRef(false)
  const navigationTimer = useRef<number | null>(null)

  const enterMatch = useCallback((matchId: string, isAdministrator = false, showTransition = true) => {
    if (navigationTimer.current !== null) window.clearTimeout(navigationTimer.current)
    setStatus('matched')
    setAdministratorMatched(isAdministrator)
    setClaimingAdministrator(false)
    setQueueJoinedAt(null)
    const navigateToMatch = () => {
      setStatus('idle')
      setAdministratorMatched(false)
      navigate(`/match/${matchId}`)
    }
    if (!showTransition) {
      navigateToMatch()
      return
    }
    navigationTimer.current = window.setTimeout(navigateToMatch, isAdministrator ? 850 : 550)
  }, [navigate])

  useEffect(() => () => {
    if (navigationTimer.current !== null) window.clearTimeout(navigationTimer.current)
  }, [])

  useEffect(() => {
    let isCurrent = true
    const restoreState = async () => {
      setStatus('checking')
      setError(null)
      setClaimingAdministrator(false)
      try {
        const activeMatch = await getActiveMatch(userId)
        if (!isCurrent) return
        if (activeMatch) {
          enterMatch(activeMatch.id, false, false)
          return
        }

        const queueEntry = await getOwnQueueEntry(userId)
        if (!isCurrent) return
        if (queueEntry?.status === 'waiting') {
          setQueueJoinedAt(queueEntry.joined_at)
          setStatus('searching')
        } else {
          setQueueJoinedAt(null)
          setStatus('idle')
        }
      } catch (restoreError) {
        if (isCurrent) {
          setError(matchmakingErrorMessage(restoreError, 'Unable to restore matchmaking status. Please try again.'))
          setStatus('error')
        }
      }
    }
    void restoreState()
    return () => { isCurrent = false }
  }, [enterMatch, userId])

  useEffect(() => {
    if (status !== 'searching') return
    const channel = supabase
      .channel(`matchmaking:${userId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'matchmaking_queue', filter: `player_id=eq.${userId}` },
        (payload) => {
          if (payload.eventType === 'DELETE') {
            setQueueJoinedAt(null)
            setClaimingAdministrator(false)
            setStatus('idle')
            return
          }
          const entry = payload.new as QueueEntry
          if (entry.status === 'matched' && entry.matched_match_id && !claimInFlight.current) {
            void matchHasSystemPlayer(entry.matched_match_id)
              .then((isAdministrator) => enterMatch(entry.matched_match_id!, isAdministrator))
              .catch(() => enterMatch(entry.matched_match_id!))
          } else if (entry.status === 'cancelled') {
            setQueueJoinedAt(null)
            setClaimingAdministrator(false)
            setStatus('idle')
          } else if (entry.status === 'waiting' && entry.joined_at !== queueJoinedAt) {
            setQueueJoinedAt(entry.joined_at)
          }
        },
      )
      .subscribe((subscriptionStatus) => {
        if (subscriptionStatus === 'CHANNEL_ERROR' || subscriptionStatus === 'TIMED_OUT') {
          setError('The live matchmaking connection was interrupted. Try searching again.')
          setStatus('error')
        }
      })
    return () => { void supabase.removeChannel(channel) }
  }, [enterMatch, queueJoinedAt, status, userId])

  useEffect(() => {
    if (status !== 'searching' || !queueJoinedAt) {
      return
    }

    let isCurrent = true
    let claimTimer: number | null = null
    const joinedAtMs = new Date(queueJoinedAt).getTime()
    const fallbackAtMs = joinedAtMs + ADMINISTRATOR_MATCH_TIMEOUT_SECONDS * 1000

    const scheduleClaim = (delayMs: number) => {
      if (claimTimer !== null) window.clearTimeout(claimTimer)
      claimTimer = window.setTimeout(attemptClaim, Math.max(0, delayMs))
    }

    const attemptClaim = () => {
      if (!isCurrent || claimInFlight.current) return
      const remainingMs = fallbackAtMs - Date.now()
      if (remainingMs > 0) {
        scheduleClaim(remainingMs)
        return
      }

      claimInFlight.current = true
      setClaimingAdministrator(true)
      void claimAdministratorMatch()
        .then(async (result) => {
          if (!isCurrent) return
          if (result.match_id && result.result_status !== 'waiting') {
            const isAdministrator = result.result_status === 'administrator_matched'
              || await matchHasSystemPlayer(result.match_id).catch(() => false)
            if (isCurrent) enterMatch(result.match_id, isAdministrator)
            return
          }
          setClaimingAdministrator(false)
          scheduleClaim(Math.max(250, result.retry_after_seconds * 1000))
        })
        .catch((claimError) => {
          if (!isCurrent) return
          setClaimingAdministrator(false)
          setError(matchmakingErrorMessage(claimError, 'Unable to contact the Administrator. Please try matchmaking again.'))
          setStatus('error')
        })
        .finally(() => { claimInFlight.current = false })
    }

    const refreshAfterBackground = () => {
      if (document.visibilityState === 'visible' && Date.now() >= fallbackAtMs) attemptClaim()
    }
    scheduleClaim(fallbackAtMs - Date.now())
    document.addEventListener('visibilitychange', refreshAfterBackground)
    window.addEventListener('focus', refreshAfterBackground)
    return () => {
      isCurrent = false
      if (claimTimer !== null) window.clearTimeout(claimTimer)
      document.removeEventListener('visibilitychange', refreshAfterBackground)
      window.removeEventListener('focus', refreshAfterBackground)
    }
  }, [enterMatch, queueJoinedAt, status])

  const findMatch = useCallback(async () => {
    if (status !== 'idle' && status !== 'error') return
    setStatus('joining')
    setError(null)
    setClaimingAdministrator(false)
    setAdministratorMatched(false)
    try {
      const result = await findOrCreateMatch()
      if ((result.result_status === 'matched' || result.result_status === 'existing_match') && result.match_id) {
        const isAdministrator = result.result_status === 'existing_match'
          ? await matchHasSystemPlayer(result.match_id).catch(() => false)
          : false
        enterMatch(result.match_id, isAdministrator)
        return
      }

      const queueEntry = await getOwnQueueEntry(userId)
      if (queueEntry?.status === 'matched' && queueEntry.matched_match_id) {
        const isAdministrator = await matchHasSystemPlayer(queueEntry.matched_match_id).catch(() => false)
        enterMatch(queueEntry.matched_match_id, isAdministrator)
      } else if (queueEntry?.status === 'waiting') {
        setQueueJoinedAt(queueEntry.joined_at)
        setStatus('searching')
      } else {
        throw new Error('Matchmaking queue entry was not created.')
      }
    } catch (joinError) {
      setError(matchmakingErrorMessage(joinError, 'Unable to join matchmaking. Please try again.'))
      setStatus('error')
    }
  }, [enterMatch, status, userId])

  const cancelSearch = useCallback(async (navigateIfMatched = true) => {
    if (status !== 'searching' && status !== 'error') return
    setStatus('cancelling')
    setError(null)
    try {
      const result = await cancelMatchmaking()
      if (result.result_status === 'matched' && result.match_id && navigateIfMatched) {
        const isAdministrator = await matchHasSystemPlayer(result.match_id).catch(() => false)
        enterMatch(result.match_id, isAdministrator)
      } else {
        setQueueJoinedAt(null)
        setClaimingAdministrator(false)
        setStatus('idle')
      }
    } catch (cancelError) {
      setError(matchmakingErrorMessage(cancelError, 'Unable to cancel matchmaking. Please try again.'))
      setStatus('error')
    }
  }, [enterMatch, status])

  return { status, error, queueJoinedAt, claimingAdministrator, administratorMatched, findMatch, cancelSearch }
}
