import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../../lib/supabase'
import type { MatchStatus } from '../../matchmaking/types'
import { cancelActiveMatch, forfeitActiveMatch, loadMatchExitState, type MatchExitState } from '../services/matchExit'

const preBattleStatuses: MatchStatus[] = ['waiting', 'initiative', 'oc_selection', 'draft', 'oc_preparation']

function exitErrorMessage(cause: unknown, mode: 'cancel' | 'forfeit'): string {
  if (typeof cause === 'object' && cause !== null && 'code' in cause && cause.code === 'PGRST202') {
    return 'Match exit setup is incomplete. Run docs/supabase_match_exit.sql in Supabase, then refresh this page.'
  }
  return `Could not ${mode} the match. Try again.`
}

export function MatchExitBoundary({ matchId, currentUserId, children }: { matchId: string; currentUserId: string; children: ReactNode }) {
  const navigate = useNavigate()
  const [match, setMatch] = useState<MatchExitState | null>(null)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    try { setMatch(await loadMatchExitState(matchId)) }
    catch (cause) {
      console.error('Match exit state load failed', cause)
      setError('Match controls could not be loaded. Refresh and try again.')
    }
  }, [matchId])

  useEffect(() => {
    void Promise.resolve().then(refresh)
    const channel = supabase.channel(`match-exit:${matchId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void refresh() })
      .subscribe()
    return () => { void supabase.removeChannel(channel) }
  }, [matchId, refresh])

  useEffect(() => {
    if (match?.status !== 'cancelled') return
    const timer = window.setTimeout(() => navigate('/', { replace: true }), 1400)
    return () => window.clearTimeout(timer)
  }, [match?.status, navigate])

  useEffect(() => {
    if (match?.status !== 'completed' || match.forfeited_by !== currentUserId) return
    const timer = window.setTimeout(() => navigate('/', { replace: true }), 1400)
    return () => window.clearTimeout(timer)
  }, [currentUserId, match, navigate])

  const mode = match?.status === 'battle' ? 'forfeit' : preBattleStatuses.includes(match?.status ?? 'completed') ? 'cancel' : null
  const leaving = match?.status === 'cancelled' ? 'cancelled' : match?.status === 'completed' && match.forfeited_by === currentUserId ? 'forfeited' : null
  const unranked = match?.match_source === 'direct_challenge'
  const confirm = async () => {
    if (!mode || pending) return
    setPending(true)
    setError(null)
    try {
      if (mode === 'forfeit') await forfeitActiveMatch(matchId)
      else await cancelActiveMatch(matchId)
      await refresh()
    } catch (cause) {
      console.error('Match exit failed', cause)
      try {
        const latest = await loadMatchExitState(matchId)
        setMatch(latest)
        if (latest.status !== 'cancelled' && latest.status !== 'completed') setError(exitErrorMessage(cause, mode))
      } catch { setError(exitErrorMessage(cause, mode)) }
    } finally { setPending(false) }
  }

  if (leaving) return <main className="game-page match-exit-terminal"><section><p className="eyebrow">{unranked ? 'Direct Challenge · Unranked' : 'Match Update'}</p><h1>{leaving === 'forfeited' ? 'Match Forfeited' : 'Match Cancelled'}</h1>{!unranked && leaving === 'forfeited' && (match?.boon_points_earned ?? 0) > 0 && <p className="boon-forfeit-reward">+{match?.boon_points_earned.toLocaleString()} BP</p>}<p>{leaving === 'forfeited' ? 'Returning to the lobby...' : 'The match has ended. Returning to the lobby...'}</p></section></main>

  if (match?.status === 'completed' && match.forfeited_by && match.forfeited_by !== currentUserId) {
    return <main className="game-page match-exit-terminal"><section><p className="eyebrow">{unranked ? 'Challenge Complete' : 'Match Complete'}</p><h1>Victory</h1><p>Your opponent forfeited the match.</p>{unranked ? <p className="unranked-result-label">Direct Challenge · Unranked Match</p> : match.boon_points_earned > 0 && <div className="boon-match-reward"><span>Boon Points Earned</span><strong>+{match.boon_points_earned.toLocaleString()} BP</strong><small>Balance: {match.boon_point_balance.toLocaleString()} BP</small></div>}<button className="button button-primary" onClick={() => navigate('/', { replace: true })}>Return to Lobby</button></section></main>
  }

  return <>
    {children}
    {mode && <button type="button" className="match-exit-button" aria-label={mode === 'forfeit' ? 'Forfeit Match' : 'Cancel Match'} title={mode === 'forfeit' ? 'Forfeit Match' : 'Cancel Match'} onClick={() => { setError(null); setDialogOpen(true) }}>×</button>}
    {dialogOpen && mode && <div className="match-exit-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !pending) setDialogOpen(false) }}>
      <section className="match-exit-dialog" role="dialog" aria-modal="true" aria-labelledby="match-exit-title">
        <p className="eyebrow">Leave Arena</p><h2 id="match-exit-title">{mode === 'forfeit' ? 'Forfeit this match?' : 'Cancel this match?'}</h2>
        <p>{mode === 'forfeit' ? 'You will leave the current battle and your opponent will be awarded the win.' : 'You will leave the current match and return to the lobby.'}</p>
        {error && <p className="match-exit-error" role="alert">{error}</p>}
        <div><button className="button button-secondary" disabled={pending} onClick={() => setDialogOpen(false)}>Keep Playing</button><button className="button match-exit-confirm" disabled={pending} onClick={() => void confirm()}>{pending ? mode === 'forfeit' ? 'Forfeiting Match...' : 'Cancelling Match...' : mode === 'forfeit' ? 'Forfeit Match' : 'Cancel Match'}</button></div>
      </section>
    </div>}
  </>
}
