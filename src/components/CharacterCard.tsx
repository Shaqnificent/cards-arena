import { useState } from 'react'
import type { Character } from '../types/character'

interface CharacterCardProps {
  character: Character
}

export function CharacterCard({ character }: CharacterCardProps) {
  const [imageFailed, setImageFailed] = useState(false)

  const showImage = character.image_url && !imageFailed

  return (
    <article className="character-card">
      <div className="character-image-wrap">
        {showImage ? (
          <img
            className="character-image"
            src={character.image_url ?? undefined}
            alt={character.name}
            loading="lazy"
            onError={() => setImageFailed(true)}
          />
        ) : (
          <div className="character-image-fallback" aria-label={`${character.name} image unavailable`}>
            <span>{character.name.charAt(0)}</span>
          </div>
        )}
        <div className="overall-badge"><strong>{character.overall}</strong><span>OVR</span></div>
      </div>
      <div className="character-details">
        <p className="character-verse">{character.verses?.name ?? 'Unknown Verse'}</p>
        <h2>{character.name}</h2>
        {character.version && <p className="character-version">{character.version}</p>}
        <div className="character-power"><span>Global Power</span><strong>{character.power_score.toLocaleString()}</strong></div>
      </div>
    </article>
  )
}
