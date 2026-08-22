import type { LocalGameState } from '../types'
import { GameCard } from './GameCard'

interface BattleBoardProps {
  state: LocalGameState
  onSelect: (id: string) => void
  onLock: () => void
  onContinue: () => void
}

export function BattleBoard({ state, onSelect, onLock, onContinue }: BattleBoardProps) {
  const { battle } = state
  const matchPoint = battle.playerScore >= 3 || battle.opponentScore >= 3 || battle.round >= 5

  return (
    <section className="battle-board">
      <header className="battle-score">
        <div><span>You</span><strong>{battle.playerScore}</strong></div>
        <p>Round {battle.round}<small>First to 3</small></p>
        <div><span>Opponent</span><strong>{battle.opponentScore}</strong></div>
      </header>

      {battle.reveal ? (
        <div className="battle-reveal">
          <GameCard character={battle.reveal.playerCard} />
          <div className="versus-result"><span>VS</span><strong>{battle.reveal.winner === 'player' ? 'You Win' : battle.reveal.winner === 'opponent' ? 'Opponent Wins' : 'Power Tie'}</strong></div>
          <GameCard character={battle.reveal.opponentCard} />
          <button className="button button-primary" onClick={onContinue}>{matchPoint ? 'View Result' : 'Next Round'}</button>
        </div>
      ) : (
        <>
          <h2>Opponent team</h2>
          <div className="opponent-roster">
            {state.opponent.team.map((character) => (
              <span key={character.id} className={battle.opponentUsedIds.includes(character.id) ? 'used' : undefined}>
                {character.name} <b>{character.overall}</b>
              </span>
            ))}
          </div>
          <div className="opponent-hidden"><span>?</span><p>Opponent selection hidden</p></div>
          <h2>Choose your fighter</h2>
          <div className="battle-hand">
            {state.player.team.map((character) => (
              <GameCard
                key={character.id} character={character} compact
                selected={battle.selectedPlayerId === character.id}
                used={battle.playerUsedIds.includes(character.id)}
                onClick={() => onSelect(character.id)}
              />
            ))}
          </div>
          <button className="button button-primary lock-button" disabled={!battle.selectedPlayerId} onClick={onLock}>Lock In</button>
        </>
      )}
    </section>
  )
}
