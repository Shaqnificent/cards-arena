import { Link } from 'react-router-dom'
import type { LocalGameState } from '../types'

interface MatchResultProps { state: LocalGameState; onRestart: () => void }

export function MatchResult({ state, onRestart }: MatchResultProps) {
  const title = state.winner === 'player' ? 'Victory' : state.winner === 'opponent' ? 'Defeat' : 'Draw'
  return (
    <section className="match-result">
      <p className="eyebrow">Local Match Complete</p>
      <h1>{title}</h1>
      <div className="final-score"><span>You <b>{state.battle.playerScore}</b></span><i>—</i><span><b>{state.battle.opponentScore}</b> Opponent</span></div>
      <p>Local test matches do not affect your public record.</p>
      <div className="result-actions">
        <button className="button button-primary" onClick={onRestart}>Play Again</button>
        <Link className="button button-secondary" to="/">Return to Lobby</Link>
      </div>
    </section>
  )
}
