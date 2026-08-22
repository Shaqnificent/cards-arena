import { useState } from 'react'
import type { Character } from '../../../types/character'

interface GameCardProps {
  character: Character
  compact?: boolean
  selected?: boolean
  used?: boolean
  onClick?: () => void
  onHover?: () => void
}

export function GameCard({ character, compact = false, selected = false, used = false, onClick, onHover }: GameCardProps) {
  const [imageFailed, setImageFailed] = useState(false)
  return (
    <button
      type="button"
      className={`game-card${compact ? ' compact' : ''}${selected ? ' selected' : ''}${used ? ' used' : ''}`}
      onClick={onClick}
      onMouseEnter={used || !onClick ? undefined : onHover}
      disabled={used || !onClick}
    >
      <div className="game-card-image">
        {character.image_url && !imageFailed ? (
          <img src={character.image_url} alt="" onError={() => setImageFailed(true)} />
        ) : (
          <span className="game-card-fallback">{character.name.charAt(0)}</span>
        )}
        <b>{character.overall}<small>OVR</small></b>
        {selected && <i className="game-card-check" aria-hidden="true">✓</i>}
        {used && <em className="game-card-state">USED</em>}
      </div>
      <div className="game-card-content">
        <span className="game-card-verse">{character.verses?.name ?? 'Unknown Verse'}</span>
        <strong>{character.name}</strong>
        {character.version && <span className="game-card-version">{character.version}</span>}
      </div>
    </button>
  )
}
