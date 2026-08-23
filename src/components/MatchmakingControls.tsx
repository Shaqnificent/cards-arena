import { Link } from 'react-router-dom'
import type { MatchmakingState } from '../features/matchmaking/types'

interface MatchmakingControlsProps {
  status: MatchmakingState
  error: string | null
  administratorMatched: boolean
  findMatch: () => Promise<void>
}

export function MatchmakingControls({ status, error, administratorMatched, findMatch }: MatchmakingControlsProps) {
  const busy = status === 'checking' || status === 'joining' || status === 'cancelling' || status === 'matched'

  return (
    <section className="matchmaking-controls" aria-live="polite">
      {status === 'searching' || status === 'cancelling' ? (
        <>
          <div className="searching-indicator">
            <span />
            <p>{status === 'cancelling' ? 'Cancelling search...' : 'Searching for opponent...'}</p>
          </div>
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
