import { useEffect, useState } from 'react'
import { ADMINISTRATOR_MATCH_TIMEOUT_SECONDS } from '../features/matchmaking/config'
import type { MatchmakingController } from '../features/matchmaking/types'

function remainingSeconds(joinedAt: string, now: number): number | null {
  const joinedAtMs = new Date(joinedAt).getTime()
  if (!Number.isFinite(joinedAtMs)) return null
  const elapsedSeconds = Math.max(0, Math.floor((now - joinedAtMs) / 1000))
  return Math.max(0, ADMINISTRATOR_MATCH_TIMEOUT_SECONDS - elapsedSeconds)
}

export function MatchmakingToast({ matchmaking }: { matchmaking: MatchmakingController }) {
  const [now, setNow] = useState(() => Date.now())
  const { status, queueJoinedAt, claimingAdministrator, administratorMatched, error, cancelSearch } = matchmaking
  const queued = queueJoinedAt !== null
  const visible = status === 'searching' || status === 'cancelling' || status === 'matched' || (status === 'error' && queued)

  useEffect(() => {
    if (status !== 'searching' || !queueJoinedAt || claimingAdministrator) return
    const updateNow = () => setNow(Date.now())
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') updateNow()
    }
    updateNow()
    const timer = window.setInterval(updateNow, 500)
    document.addEventListener('visibilitychange', refreshWhenVisible)
    window.addEventListener('focus', updateNow)
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', refreshWhenVisible)
      window.removeEventListener('focus', updateNow)
    }
  }, [claimingAdministrator, queueJoinedAt, status])

  if (!visible) return null

  const seconds = queueJoinedAt ? remainingSeconds(queueJoinedAt, now) : null
  const isClaiming = status === 'searching' && (claimingAdministrator || seconds === 0)
  const announcement = status === 'matched'
    ? administratorMatched ? 'Administrator has entered the Arena.' : 'Opponent found.'
    : status === 'cancelling'
      ? 'Cancelling matchmaking.'
      : status === 'error'
        ? 'Matchmaking was interrupted.'
        : 'Searching for opponent.'

  return <aside className={`global-matchmaking-toast state-${status}`} aria-label="Matchmaking status">
    <span className="sr-only" aria-live="polite" aria-atomic="true">{announcement}</span>
    <div className="matchmaking-toast-heading">
      <i aria-hidden="true" />
      <strong>{status === 'matched'
        ? administratorMatched ? 'Administrator has entered the Arena' : 'Opponent found'
        : status === 'cancelling'
          ? 'Cancelling search'
          : status === 'error'
            ? 'Matchmaking interrupted'
            : 'Searching for opponent'}</strong>
    </div>
    <div className="matchmaking-toast-body">
      {status === 'matched'
        ? <p>{administratorMatched ? 'No challenger answered the queue.' : 'Entering the Arena...'}</p>
        : status === 'cancelling'
          ? <p>Leaving the matchmaking queue...</p>
          : status === 'error'
            ? <p>{error ?? 'Unable to verify the current queue state.'}</p>
            : isClaiming
              ? <p>Contacting Administrator...</p>
              : <p>Administrator enters in <b aria-live="off">{seconds ?? '--'}s</b></p>}
      {(status === 'searching' || status === 'error') && <button type="button" disabled={claimingAdministrator} onClick={() => void cancelSearch()}>{claimingAdministrator ? 'Verifying...' : 'Cancel Search'}</button>}
    </div>
  </aside>
}
