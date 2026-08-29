import type { CSSProperties } from 'react'
import type { Character } from '../types/character'
import { CharacterArtwork } from './CharacterArtwork'
import { TiltCard } from './TiltCard'

interface CharacterCardProps {
  character: Character
}

const characterAccents = ['#8b5cf6','#22b8f0','#d946ef','#a855f7','#6366f1'] as const

export function CharacterCard({ character }: CharacterCardProps) {
  const accent = characterAccents[Math.abs(character.verse_id) % characterAccents.length]
  return (
    <TiltCard className="character-card" style={{ '--character-accent': accent } as CSSProperties}>
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
    </TiltCard>
  )
}
