import { useState } from 'react'
import { getRandomCharacterTheme, isRandomCharacter } from '../lib/randomCharacterTheme'
import type { Character } from '../types/character'

interface CharacterArtworkProps {
  character: Character
  imageClassName: string
  fallbackClassName: string
  alt?: string
  loading?: 'eager' | 'lazy'
}

export function CharacterArtwork({
  character,
  imageClassName,
  fallbackClassName,
  alt = '',
  loading = 'eager',
}: CharacterArtworkProps) {
  const [failedImageUrl, setFailedImageUrl] = useState<string | null>(null)
  const randomCharacter = isRandomCharacter(character)
  const theme = randomCharacter ? getRandomCharacterTheme(character) : null
  const showImage = Boolean(character.image_url) && failedImageUrl !== character.image_url

  return <>
    {theme && <span className={`random-character-background random-theme-${theme}`} aria-hidden="true" />}
    {showImage ? <img
      className={`${imageClassName}${randomCharacter ? ' random-character-portrait' : ''}`}
      src={character.image_url ?? undefined}
      alt={alt}
      loading={loading}
      onError={() => setFailedImageUrl(character.image_url)}
    /> : <span
      className={`${fallbackClassName}${randomCharacter ? ' random-character-fallback' : ''}`}
      aria-label={alt ? `${character.name} image unavailable` : undefined}
      aria-hidden={alt ? undefined : 'true'}
    ><span>{character.name.charAt(0)}</span></span>}
  </>
}
