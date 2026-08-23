import type { Character } from '../types/character'
import { CharacterArtwork } from './CharacterArtwork'

interface CharacterCardProps {
  character: Character
}

export function CharacterCard({ character }: CharacterCardProps) {
  return (
    <article className="character-card">
      <div className="character-image-wrap">
        <CharacterArtwork
          character={character}
          imageClassName="character-image"
          fallbackClassName="character-image-fallback"
          alt={character.name}
          loading="lazy"
        />
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
