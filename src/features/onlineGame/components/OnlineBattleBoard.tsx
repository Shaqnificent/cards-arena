import { useState } from 'react'
import { Link } from 'react-router-dom'
import { GameCard } from '../../game/components/GameCard'
import type { OnlineBattleAction, OnlineBattleFighter, OnlineBattleState } from '../battleTypes'

interface Props {
  state: OnlineBattleState
  pendingAction: OnlineBattleAction
  message: string | null
  onLock: (fighterId: string) => Promise<void>
  onAdvance: () => Promise<void>
}

function fighter(state: OnlineBattleState, id: string | null | undefined): OnlineBattleFighter | null {
  if (!id) return null
  return [...state.yourTeam, ...state.opponentTeam].find((item) => item.id === id) ?? null
}

export function OnlineBattleBoard({ state, pendingAction, message, onLock, onAdvance }: Props) {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const yourSelection = fighter(state, state.yourSelectionId)
  const revealed = state.battleState !== 'selecting' ? state.latestRound : null
  const yourReveal = fighter(state, revealed?.yourFighterId)
  const opponentReveal = fighter(state, revealed?.opponentFighterId)
  const victory = state.matchWinnerId === state.yourPlayerId
  const draw = state.status === 'completed' && !state.matchWinnerId

  if (state.status === 'completed') {
    return <section className="match-result">
      <p className="eyebrow">Match Complete</p><h1>{draw ? 'Draw' : victory ? 'Victory' : 'Defeat'}</h1>
      <div className="final-score"><span>{state.yourProfile.username} <b>{state.yourScore}</b></span><i>—</i><span><b>{state.opponentScore}</b> {state.opponentProfile.username}</span></div>
      <p>Your Record: {state.yourProfile.wins} Wins • {state.yourProfile.losses} Losses</p>
      <Link className="button button-primary" to="/">Return to Lobby</Link>
    </section>
  }

  return <section className="battle-board">
    <header className="battle-score">
      <div><span>{state.yourProfile.username}</span><strong>{state.yourScore}</strong></div>
      <p>Round {state.roundNumber}<small>First to 3</small></p>
      <div><span>{state.opponentProfile.username}</span><strong>{state.opponentScore}</strong></div>
    </header>
    {message && <p className="online-draft-message" role="status">{message}</p>}
    {revealed && yourReveal && opponentReveal ? <div className="battle-reveal">
      <GameCard character={yourReveal.character} />
      <div className="versus-result"><span>VS</span><strong>{revealed.winnerPlayerId === state.yourPlayerId ? 'You Win' : revealed.winnerPlayerId === state.opponentPlayerId ? 'Opponent Wins' : 'Power Tie'}</strong></div>
      <GameCard character={opponentReveal.character} />
      <button className="button button-primary" disabled={pendingAction !== null} onClick={() => void onAdvance()}>{pendingAction === 'advance' ? 'Advancing...' : 'Next Round'}</button>
    </div> : <>
      <div className="opponent-roster"><h2>Opponent Team</h2>{state.opponentTeam.map((item) => <span key={item.id} className={item.used ? 'used' : undefined}>{item.character.name}</span>)}</div>
      <h2>{yourSelection ? 'Locked In' : 'Choose Your Fighter'}</h2>
      <div className="battle-hand">{state.yourTeam.map((item) => <GameCard key={item.id} character={item.character} compact used={item.used} selected={(yourSelection?.id ?? selectedId) === item.id} onClick={yourSelection ? undefined : () => setSelectedId(item.id)} />)}</div>
      {yourSelection ? <p className="battle-lock-status">{state.opponentLocked ? 'Opponent locked in. Resolving round...' : 'Waiting for opponent...'}</p>
        : <button className="button button-primary lock-button" disabled={!selectedId || pendingAction !== null} onClick={() => selectedId && void onLock(selectedId)}>{pendingAction === 'lock' ? 'Locking...' : 'Lock In'}</button>}
      {!yourSelection && state.opponentLocked && <p className="battle-lock-status">Opponent has locked in.</p>}
    </>}
  </section>
}
