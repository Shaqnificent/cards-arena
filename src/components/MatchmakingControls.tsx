import { Link } from 'react-router-dom'
import type { MatchmakingState } from '../features/matchmaking/types'

interface MatchmakingControlsProps {
  status: MatchmakingState
  error: string | null
  administratorCountdownSeconds: number | null
  administratorMatched: boolean
  findMatch: () => Promise<void>
  cancelSearch: () => Promise<void>
}

export function MatchmakingControls({ status, error, administratorCountdownSeconds, administratorMatched, findMatch, cancelSearch }: MatchmakingControlsProps) {
  const busy = status === 'checking' || status === 'joining' || status === 'cancelling' || status === 'matched'

  return (
    <section className="matchmaking-controls" aria-live="polite">
      {status === 'searching' || status === 'cancelling' ? (
        <>
          <div className="searching-indicator">
            <span />
            <div>
              <p>{status === 'cancelling' ? 'Cancelling search...' : 'Searching for opponent...'}</p>
              {status === 'searching' && administratorCountdownSeconds !== null && <small>Administrator enters in {administratorCountdownSeconds}s</small>}
            </div>
          </div>
          <button className="button button-secondary" disabled={status === 'cancelling'} onClick={() => void cancelSearch()}>Cancel Search</button>
        </>
      ) : (
        <button className="button button-primary find-match" disabled={busy} onClick={() => void findMatch()}>
          <span aria-hidden="true">⌕</span>
          {status === 'checking'
            ? 'Checking Match Status...'
            : status === 'joining'
              ? 'Joining Queue...'
              : status === 'matched'
                ? administratorMatched ? 'Administrator has entered the Arena' : 'Match Found'
                : 'Find Match'}
        </button>
      )}
      {error && <p className="matchmaking-error" role="alert">{error}</p>}
      <Link className="local-match-link" to="/play/test"><span aria-hidden="true">▣</span> Play local prototype instead</Link>
    </section>
  )
}
