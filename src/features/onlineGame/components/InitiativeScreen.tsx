import { useState } from 'react'
import type { InitiativeChoice, OnlineInitiativeState } from '../types'

const choices: InitiativeChoice[] = ['rock', 'paper', 'scissors']
const symbols: Record<InitiativeChoice, string> = { rock: '●', paper: '▰', scissors: '✂' }

interface Props { initiative: OnlineInitiativeState; message: string | null; onLock: (choice: InitiativeChoice) => Promise<void> }

export function InitiativeScreen({ initiative, message, onLock }: Props) {
  const [selected, setSelected] = useState<InitiativeChoice | null>(null)
  const [locking, setLocking] = useState(false)
  const revealed = initiative.initiativeState === 'revealed'
  const youWon = initiative.winnerPlayerId === initiative.yourPlayerId
  const winnerName = youWon ? initiative.yourProfile.username : initiative.opponentProfile.username

  const lock = async () => {
    if (!selected || locking) return
    setLocking(true)
    await onLock(selected)
    setLocking(false)
  }

  return <main className="initiative-page"><section className="initiative-card" aria-live="polite">
    <p className="eyebrow">Pre-Draft · Round {initiative.initiativeRound}</p><h1>Initiative</h1>
    {message && <p className="online-draft-message" role="status">{message}</p>}
    {revealed && initiative.yourChoice && initiative.opponentChoice ? <>
      <p className="initiative-instruction">Initiative Reveal</p>
      <div className="initiative-reveal"><div><small>You</small><b>{symbols[initiative.yourChoice]}</b><strong>{initiative.yourChoice}</strong></div><i>VS</i><div><small>{initiative.opponentProfile.username}</small><b>{symbols[initiative.opponentChoice]}</b><strong>{initiative.opponentChoice}</strong></div></div>
      <h2>{initiative.isDraw ? 'Draw' : youWon ? 'You win initiative' : `${winnerName} wins initiative`}</h2>
      <p>{initiative.isDraw ? 'Choose again next round.' : `${winnerName} gets first draft priority.`}</p>
      <small>{initiative.isDraw ? 'Preparing the next round...' : 'Preparing secret OC selection...'}</small>
    </> : initiative.yourChoice ? <>
      <p className="initiative-instruction">Your move is locked</p><div className="initiative-locked"><b>{symbols[initiative.yourChoice]}</b><strong>{initiative.yourChoice}</strong></div>
      <h2>{initiative.opponentLocked ? 'Opponent locked in' : 'Waiting for opponent...'}</h2><p>Your choice remains hidden until both players lock.</p>
    </> : <>
      <p className="initiative-instruction">Choose your move</p><p className="initiative-helper">Your choice stays hidden until both players lock.</p>
      <div className="initiative-choices">{choices.map((choice) => <button type="button" key={choice} className={selected === choice ? 'selected' : ''} onClick={() => setSelected(choice)}><b>{symbols[choice]}</b><span>{choice}</span></button>)}</div>
      {initiative.opponentLocked && <p className="initiative-opponent-locked">Opponent has locked in.</p>}
      <button type="button" className="button button-primary initiative-lock" disabled={!selected || locking} onClick={() => void lock()}>{locking ? 'Locking...' : 'Lock In'}</button>
    </>}
  </section></main>
}
