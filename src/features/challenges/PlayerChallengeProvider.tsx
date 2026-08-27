import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { acceptPlayerChallenge, cancelPlayerChallenge, declinePlayerChallenge, getChallengeLifecycle, getPendingPlayerChallenge, sendPlayerChallenge } from './services/playerChallenges'
import type { ChallengePlayerSummary, PlayerChallenge, PlayerChallengeContextValue, PlayerChallengeStatus } from './types'
import { PlayerChallengeContext } from './playerChallengeContext'

interface ChallengeRowEvent {
  id?: string
  challenger_id?: string
  challenged_id?: string
  status?: PlayerChallengeStatus
  match_id?: string | null
}

function challengeError(error: unknown): string {
  return error instanceof Error ? error.message : 'The challenge could not be updated. Try again.'
}

export function PlayerChallengeProvider({ userId, eligible, children }: { userId: string; eligible: boolean; children: ReactNode }) {
  const navigate = useNavigate()
  const [challenge, setChallenge] = useState<PlayerChallenge | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [pendingAction, setPendingAction] = useState<PlayerChallengeContextValue['pendingAction']>(null)
  const challengeRef = useRef<PlayerChallenge | null>(null)
  useEffect(() => { challengeRef.current = challenge }, [challenge])

  const enterMatch = useCallback((matchId: string) => {
    setChallenge(null)
    setNotice(null)
    navigate(`/match/${matchId}`)
  }, [navigate])

  const refresh = useCallback(async () => {
    if (!eligible) return
    try {
      const restored = await getPendingPlayerChallenge()
      setChallenge(restored)
    } catch (error) {
      setNotice(challengeError(error))
    }
  }, [eligible])

  useEffect(() => {
    const timer = window.setTimeout(() => { void refresh() }, 0)
    return () => window.clearTimeout(timer)
  }, [refresh])

  useEffect(() => {
    if (!eligible) return
    const onChange = (payload: { new: unknown; old: unknown; eventType: string }) => {
      const row = (payload.eventType === 'DELETE' ? payload.old : payload.new) as ChallengeRowEvent
      if (row.status === 'accepted' && row.match_id) {
        enterMatch(row.match_id)
        return
      }
      const current = challengeRef.current
      if (current && row.id === current.id && row.status && row.status !== 'pending') {
        const message = row.status === 'declined'
          ? `${current.counterpart.username} declined your challenge.`
          : row.status === 'cancelled'
            ? current.direction === 'incoming' ? `${current.counterpart.username} cancelled the challenge.` : 'Challenge cancelled.'
            : row.status === 'expired' ? 'Challenge expired.' : null
        setChallenge(null)
        if (message) setNotice(message)
        return
      }
      void refresh()
    }

    const channel = supabase.channel(`player-challenges:${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'player_challenges', filter: `challenger_id=eq.${userId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'player_challenges', filter: `challenged_id=eq.${userId}` }, onChange)
      .subscribe()
    return () => { void supabase.removeChannel(channel) }
  }, [eligible, enterMatch, refresh, userId])

  useEffect(() => {
    if (!challenge) return
    const delay = Math.max(0, new Date(challenge.expiresAt).getTime() - Date.now()) + 100
    const reconcile = async () => {
      try {
        const lifecycle = await getChallengeLifecycle(challenge.id)
        if (lifecycle?.status === 'accepted' && lifecycle.matchId) { enterMatch(lifecycle.matchId); return }
        if (lifecycle?.status === 'pending') return
        setChallenge(null)
        setNotice(lifecycle?.status === 'declined' ? `${challenge.counterpart.username} declined your challenge.` : lifecycle?.status === 'cancelled' ? 'Challenge cancelled.' : 'Challenge expired.')
      } catch { /* Realtime remains primary; retry on the next reconciliation. */ }
    }
    const expiryTimer = window.setTimeout(() => { void reconcile().then(refresh) }, delay)
    const reconcileTimer = window.setInterval(() => { void reconcile() }, 5000)
    return () => { window.clearTimeout(expiryTimer); window.clearInterval(reconcileTimer) }
  }, [challenge, enterMatch, refresh])

  const send = useCallback(async (player: ChallengePlayerSummary) => {
    if (!eligible || pendingAction || challengeRef.current) return
    setPendingAction('sending'); setNotice(null)
    try { setChallenge(await sendPlayerChallenge(player.id)) }
    catch (error) { setNotice(challengeError(error)) }
    finally { setPendingAction(null) }
  }, [eligible, pendingAction])

  const accept = useCallback(async () => {
    const current = challengeRef.current
    if (!current || current.direction !== 'incoming' || pendingAction) return
    setPendingAction('accepting'); setNotice(null)
    try {
      const result = await acceptPlayerChallenge(current.id)
      if (result.status === 'accepted' && result.matchId) enterMatch(result.matchId)
      else { setChallenge(null); setNotice('Player is currently unavailable.') }
    } catch (error) { setNotice(challengeError(error)) }
    finally { setPendingAction(null) }
  }, [enterMatch, pendingAction])

  const decline = useCallback(async () => {
    const current = challengeRef.current
    if (!current || current.direction !== 'incoming' || pendingAction) return
    setPendingAction('declining')
    try { await declinePlayerChallenge(current.id); setChallenge(null) }
    catch (error) { setNotice(challengeError(error)) }
    finally { setPendingAction(null) }
  }, [pendingAction])

  const cancel = useCallback(async () => {
    const current = challengeRef.current
    if (!current || current.direction !== 'outgoing' || pendingAction) return
    setPendingAction('cancelling')
    try { await cancelPlayerChallenge(current.id); setChallenge(null); setNotice('Challenge cancelled.') }
    catch (error) { setNotice(challengeError(error)) }
    finally { setPendingAction(null) }
  }, [pendingAction])

  const value = useMemo<PlayerChallengeContextValue>(() => ({ challenge, notice, pendingAction, eligible, send, accept, decline, cancel, clearNotice: () => setNotice(null) }), [accept, cancel, challenge, decline, eligible, notice, pendingAction, send])
  return <PlayerChallengeContext.Provider value={value}>{children}</PlayerChallengeContext.Provider>
}
