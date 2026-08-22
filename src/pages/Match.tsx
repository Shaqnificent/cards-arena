import { useParams } from 'react-router-dom'
import { LoadingScreen } from '../components/LoadingScreen'
import { OnlineDraftBoard } from '../features/onlineGame/components/OnlineDraftBoard'
import { OnlineBattleBoard } from '../features/onlineGame/components/OnlineBattleBoard'
import { InitiativeScreen } from '../features/onlineGame/components/InitiativeScreen'
import { useOnlineBattle } from '../features/onlineGame/hooks/useOnlineBattle'
import { useOnlineDraft } from '../features/onlineGame/hooks/useOnlineDraft'

interface MatchProps { currentUserId: string }

export function Match({ currentUserId }: MatchProps) {
  const { matchId } = useParams()

  if (!matchId) return <MatchError message="Match not found." />
  return <LoadedOnlineMatch matchId={matchId} currentUserId={currentUserId} />
}

function LoadedOnlineMatch({ matchId, currentUserId }: { matchId: string; currentUserId: string }) {
  const { state, initiative, loadState, loading, error, message, pendingAction, lockInitiative, bid, pass, fold, retry } = useOnlineDraft(matchId, currentUserId)

  if (loadState === 'initiative' && initiative) return <InitiativeScreen key={initiative.initiativeRound} initiative={initiative} message={message} onLock={lockInitiative} />

  if (loading && !state) {
    const loadingMessage = loadState === 'loading-match' ? 'Loading online match...'
      : loadState === 'determining-initiative' ? 'Determining initiative...'
      : loadState === 'initializing-draft' ? 'Preparing draft...'
      : 'Loading authoritative draft state...'
    return <LoadingScreen message={loadingMessage} />
  }
  if (error || !state) return <MatchError message={error ?? 'This match is unavailable.'} onRetry={() => void retry()} />

  if (state.match.status === 'battle' || state.match.status === 'completed') {
    return <LoadedOnlineBattle matchId={matchId} />
  }

  return (
    <main className="game-page">
      <header className="game-header"><span className="brand-link">ANIME ARENA</span><span>Server-Authoritative Draft</span><span className="nav-link">Match {matchId.slice(0, 8)}</span></header>
      <OnlineDraftBoard
        key={state.match.current_draft_position}
        state={state} currentUserId={currentUserId} pendingAction={pendingAction} message={message}
        onBid={bid} onPass={pass} onFold={fold}
      />
    </main>
  )
}

function LoadedOnlineBattle({ matchId }: { matchId: string }) {
  const { state, loading, error, message, pendingAction, lock, advance, retry } = useOnlineBattle(matchId)
  if (loading && !state) return <LoadingScreen message="Preparing authoritative battle..." />
  if (error || !state) return <MatchError message={error ?? 'This battle is unavailable.'} onRetry={() => void retry()} />
  return <main className="game-page">
    <header className="game-header"><span className="brand-link">ANIME ARENA</span><span>Server-Authoritative Battle</span><span className="nav-link">Match {matchId.slice(0, 8)}</span></header>
    <OnlineBattleBoard key={`${state.roundNumber}:${state.battleState}`} state={state} pendingAction={pendingAction} message={message} onLock={lock} onAdvance={advance} />
  </main>
}

function MatchError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <main className="screen"><section className="panel"><h1>Match Unavailable</h1>
      <p className="error-message" role="alert">{message}</p>
      {onRetry && <button className="button button-secondary" onClick={onRetry}>Retry</button>}
    </section></main>
  )
}
