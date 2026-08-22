import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../../lib/supabase'
import { cancelMatchmaking, findOrCreateMatch, getActiveMatch, getOwnQueueEntry } from '../services/matchmaking'
import type { MatchmakingState, QueueEntry } from '../types'

function matchmakingErrorMessage(error: unknown, fallback: string): string {
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'PGRST202') {
    return 'Matchmaking setup is incomplete. Run docs/supabase_matchmaking.sql in the Supabase SQL Editor.'
  }
  return fallback
}

export function useMatchmaking(userId: string) {
  const navigate = useNavigate()
  const [status, setStatus] = useState<MatchmakingState>('checking')
  const [error, setError] = useState<string | null>(null)

  const enterMatch = useCallback((matchId: string) => {
    setStatus('matched')
    navigate(`/match/${matchId}`)
  }, [navigate])

  useEffect(() => {
    let isCurrent = true

    const restoreState = async () => {
      try {
        const activeMatch = await getActiveMatch(userId)
        if (!isCurrent) return
        if (activeMatch) {
          enterMatch(activeMatch.id)
          return
        }

        const queueEntry = await getOwnQueueEntry(userId)
        if (!isCurrent) return
        // A matched row without an active match is stale (for example, after a
        // future completion flow). Only an active match is authoritative here.
        setStatus(queueEntry?.status === 'waiting' ? 'searching' : 'idle')
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
        { event: 'UPDATE', schema: 'public', table: 'matchmaking_queue', filter: `player_id=eq.${userId}` },
        (payload) => {
          const entry = payload.new as QueueEntry
          if (entry.status === 'matched' && entry.matched_match_id) enterMatch(entry.matched_match_id)
        },
      )
      .subscribe((subscriptionStatus) => {
        if (subscriptionStatus === 'CHANNEL_ERROR' || subscriptionStatus === 'TIMED_OUT') {
          setError('The live matchmaking connection was interrupted. Try searching again.')
          setStatus('error')
        }
      })

    return () => { void supabase.removeChannel(channel) }
  }, [enterMatch, status, userId])

  const findMatch = useCallback(async () => {
    if (status !== 'idle' && status !== 'error') return
    setStatus('joining')
    setError(null)
    try {
      const result = await findOrCreateMatch()
      if ((result.result_status === 'matched' || result.result_status === 'existing_match') && result.match_id) {
        enterMatch(result.match_id)
      } else {
        setStatus('searching')
      }
    } catch (joinError) {
      setError(matchmakingErrorMessage(joinError, 'Unable to join matchmaking. Please try again.'))
      setStatus('error')
    }
  }, [enterMatch, status])

  const cancelSearch = useCallback(async (navigateIfMatched = true) => {
    if (status !== 'searching' && status !== 'error') return
    setStatus('cancelling')
    setError(null)
    try {
      const result = await cancelMatchmaking()
      if (result.result_status === 'matched' && result.match_id && navigateIfMatched) {
        enterMatch(result.match_id)
      } else {
        setStatus('idle')
      }
    } catch (cancelError) {
      setError(matchmakingErrorMessage(cancelError, 'Unable to cancel matchmaking. Please try again.'))
      setStatus('error')
    }
  }, [enterMatch, status])

  return { status, error, findMatch, cancelSearch }
}
