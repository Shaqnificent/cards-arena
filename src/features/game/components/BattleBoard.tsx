import { useEffect, useRef } from 'react'
import { CharacterArtwork } from '../../../components/CharacterArtwork'
import type { Character } from '../../../types/character'
import type { LocalGameState } from '../types'
import { GameCard } from './GameCard'
import { useGameSounds } from '../../audio/useGameSounds'

interface BattleBoardProps {
  state: LocalGameState
  onSelect: (id: string) => void
  onLock: () => void
  onContinue: () => void
}

function OpponentTeamCard({ character, used }: { character: Character; used: boolean }) {
  return (
    <article className={`local-opponent-card${used ? ' used' : ''}`} aria-label={`${character.name}, ${character.overall} overall${used ? ', used' : ''}`}>
      <div className="local-opponent-card-media">
        <CharacterArtwork
          character={character}
          imageClassName="local-opponent-card-image"
          fallbackClassName="local-opponent-card-fallback"
          alt={character.name}
          loading="lazy"
        />
        <b className="local-opponent-card-ovr">
          {character.overall}
          <small>OVR</small>
        </b>
        {used && <span className="local-opponent-card-state" aria-hidden="true">Used</span>}
      </div>
      <div className="local-opponent-card-content">
        <span>{character.verses?.name ?? 'Unknown Verse'}</span>
        <strong>{character.name}</strong>
        <small>{character.version ?? '\u00a0'}</small>
      </div>
    </article>
  )
}

export function BattleBoard({ state, onSelect, onLock, onContinue }: BattleBoardProps) {
  const { battle } = state
  const matchPoint = battle.playerScore >= 3 || battle.opponentScore >= 3 || battle.round >= 5
  const sounds = useGameSounds()
  const soundedRound = useRef<number | null>(null)

  useEffect(() => {
    if (!battle.reveal || soundedRound.current === battle.round) return
    soundedRound.current = battle.round
    sounds.playLockIn()
    const revealTimer = window.setTimeout(sounds.playRoundReveal, 100)
    const resultTimer = window.setTimeout(() => {
      if (battle.reveal?.winner === 'player') sounds.playRoundWin()
      else if (battle.reveal?.winner === 'opponent') sounds.playRoundLose()
      else sounds.playRoundDraw()
    }, 280)
    return () => { window.clearTimeout(revealTimer); window.clearTimeout(resultTimer) }
  }, [battle.reveal, battle.round, sounds])

  const selectCard = (id: string) => {
    if (battle.selectedPlayerId === id) return
    onSelect(id)
    sounds.playCardSelect()
  }

  const continueRound = () => {
    sounds.playNextRound()
    onContinue()
  }

  return (
    <section className="battle-board local-battle-board">
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
          <button className="button button-primary" onClick={continueRound}>{matchPoint ? 'View Result' : 'Next Round'}</button>
        </div>
      ) : (
        <>
          <section className="local-opponent-team" aria-labelledby="local-opponent-team-title">
            <header className="local-opponent-team-header">
              <h2 id="local-opponent-team-title">Opponent Team</h2>
              <small>Swipe to preview enemy fighters</small>
            </header>
            <div className="local-opponent-track-shell">
              <div className="local-opponent-track">
                {state.opponent.team.map((character) => (
                  <OpponentTeamCard
                    key={character.id}
                    character={character}
                    used={battle.opponentUsedIds.includes(character.id)}
                  />
                ))}
              </div>
            </div>
          </section>
          <div className="opponent-hidden"><span>?</span><p>Opponent selection hidden</p></div>
          <h2 className="local-fighter-heading">Choose your fighter</h2>
          <div className="battle-hand local-battle-hand">
            {state.player.team.map((character) => (
              <GameCard
                key={character.id} character={character} compact
                selected={battle.selectedPlayerId === character.id}
                used={battle.playerUsedIds.includes(character.id)}
                onHover={sounds.playCardHover}
                onClick={() => selectCard(character.id)}
              />
            ))}
          </div>
          <button className="button button-primary lock-button local-lock-button" disabled={!battle.selectedPlayerId} onClick={onLock}>Lock In</button>
        </>
      )}
    </section>
  )
}
