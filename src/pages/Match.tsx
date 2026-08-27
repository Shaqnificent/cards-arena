import { useParams } from 'react-router-dom'
import { LoadingScreen } from '../components/LoadingScreen'
import { OnlineDraftBoard } from '../features/onlineGame/components/OnlineDraftBoard'
import { OnlineBattleBoard } from '../features/onlineGame/components/OnlineBattleBoard'
import { InitiativeScreen } from '../features/onlineGame/components/InitiativeScreen'
import { OcSelectionScreen } from '../features/onlineGame/components/OcSelectionScreen'
import { OcPreparationScreen } from '../features/onlineGame/components/OcPreparationScreen'
import { useOnlineBattle } from '../features/onlineGame/hooks/useOnlineBattle'
import { useOnlineDraft } from '../features/onlineGame/hooks/useOnlineDraft'
import { useOcPreparation } from '../features/onlineGame/hooks/useOcPreparation'
import { MatchExitBoundary } from '../features/onlineGame/components/MatchExitControl'
import { SoundToggle } from '../features/audio/SoundToggle'
import { AdministratorToast } from '../components/AdministratorToast'
import { useAdministratorInteractions } from '../features/onlineGame/hooks/useAdministratorInteractions'
import { useMatchSource } from '../features/onlineGame/hooks/useMatchSource'

interface MatchProps { currentUserId: string }

export function Match({ currentUserId }: MatchProps) {
  const { matchId } = useParams()

  if (!matchId) return <MatchError message="Match not found." />
  return <MatchExitBoundary matchId={matchId} currentUserId={currentUserId}><SoundToggle/><AdministratorMatchExperience matchId={matchId} currentUserId={currentUserId} /></MatchExitBoundary>
}

function AdministratorMatchExperience({ matchId, currentUserId }: { matchId: string; currentUserId: string }) {
  const { toast, notifyResultVisible } = useAdministratorInteractions(matchId, currentUserId)
  const directChallenge = useMatchSource(matchId) === 'direct_challenge'
  return <><LoadedOnlineMatch matchId={matchId} currentUserId={currentUserId} directChallenge={directChallenge} onAdministratorResultVisible={notifyResultVisible} />{toast && <AdministratorToast key={toast.context} message={toast} />}</>
}

function LoadedOnlineMatch({ matchId, currentUserId, directChallenge, onAdministratorResultVisible }: { matchId: string; currentUserId: string; directChallenge: boolean; onAdministratorResultVisible: () => void }) {
  const { state, initiative, ocSelection, loadState, loading, error, message, pendingAction, lockInitiative, lockOcSelection, bid, pass, fold, retry } = useOnlineDraft(matchId, currentUserId)

  if (loadState === 'initiative' && initiative) return <><DirectChallengeLabel visible={directChallenge}/><InitiativeScreen key={initiative.initiativeRound} initiative={initiative} message={message} onLock={lockInitiative} /></>
  if (loadState === 'oc-selection' && ocSelection) return <><DirectChallengeLabel visible={directChallenge}/><OcSelectionScreen state={ocSelection} message={message} pending={pendingAction === 'oc-lock'} onLock={lockOcSelection} /></>

  if (loading && !state) {
    const loadingMessage = loadState === 'loading-match' ? 'Loading online match...'
      : loadState === 'determining-initiative' ? 'Determining initiative...'
      : loadState === 'initializing-oc-selection' ? 'Preparing secret OC selection...'
      : loadState === 'initializing-draft' ? 'Preparing draft...'
      : 'Loading authoritative draft state...'
    return <LoadingScreen message={loadingMessage} />
  }
  if (error || !state) return <MatchError message={error ?? 'This match is unavailable.'} onRetry={() => void retry()} />

  if (state.match.status === 'battle' || state.match.status === 'completed') {
    return <LoadedOnlineBattle matchId={matchId} directChallenge={directChallenge} onAdministratorResultVisible={onAdministratorResultVisible} />
  }
  if (state.match.status === 'oc_preparation') return <LoadedOcPreparation matchId={matchId} directChallenge={directChallenge} onAdministratorResultVisible={onAdministratorResultVisible} />

  return (
    <main className="game-page">
      <header className="game-header"><span className="brand-link">ANIME ARENA</span><span>{directChallenge ? 'Direct Challenge · Unranked' : 'Server-Authoritative Draft'}</span><span className="nav-link">Match {matchId.slice(0, 8)}</span></header>
      <OnlineDraftBoard
        key={state.match.current_draft_position}
        state={state} currentUserId={currentUserId} pendingAction={pendingAction} message={message}
        onBid={bid} onPass={pass} onFold={fold}
      />
    </main>
  )
}

function LoadedOcPreparation({ matchId, directChallenge, onAdministratorResultVisible }: { matchId: string; directChallenge: boolean; onAdministratorResultVisible: () => void }) {
  const { state, loading, pending, error, lock, retry } = useOcPreparation(matchId)
  if (loading && !state) return <LoadingScreen message="Preparing your OC strategy..." />
  if (!state) return <MatchError message={error ?? 'OC preparation is unavailable.'} onRetry={() => void retry()} />
  if (state.status === 'battle' || state.status === 'completed') return <LoadedOnlineBattle matchId={matchId} directChallenge={directChallenge} onAdministratorResultVisible={onAdministratorResultVisible} />
  return <><DirectChallengeLabel visible={directChallenge}/><OcPreparationScreen state={state} pending={pending} error={error} onLock={lock} /></>
}

function LoadedOnlineBattle({ matchId, directChallenge, onAdministratorResultVisible }: { matchId: string; directChallenge: boolean; onAdministratorResultVisible: () => void }) {
  const { state, loading, error, message, pendingAction, lock, advance, retry } = useOnlineBattle(matchId)
  if (loading && !state) return <LoadingScreen message="Preparing authoritative battle..." />
  if (error || !state) return <MatchError message={error ?? 'This battle is unavailable.'} onRetry={() => void retry()} />
  return <main className="game-page">
    <header className="game-header"><span className="brand-link">ANIME ARENA</span><span>{directChallenge ? 'Direct Challenge · Unranked' : 'Server-Authoritative Battle'}</span><span className="nav-link">Match {matchId.slice(0, 8)}</span></header>
    <OnlineBattleBoard key={`${state.roundNumber}:${state.battleState}`} state={state} unranked={directChallenge} pendingAction={pendingAction} message={message} onLock={lock} onAdvance={advance} onFinalResultVisible={onAdministratorResultVisible} />
  </main>
}

function DirectChallengeLabel({ visible }: { visible: boolean }) {
  return visible ? <div className="direct-challenge-mode" role="status"><strong>Direct Challenge</strong><span>Unranked</span></div> : null
}

function MatchError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <main className="screen"><section className="panel"><h1>Match Unavailable</h1>
      <p className="error-message" role="alert">{message}</p>
      {onRetry && <button className="button button-secondary" onClick={onRetry}>Retry</button>}
    </section></main>
  )
}
