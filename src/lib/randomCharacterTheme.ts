import type { Character } from '../types/character'
import type { CharacterVerse, Verse } from '../types/verse'

export const RANDOM_CHARACTER_THEMES = [
  'slate',
  'crimson',
  'forest',
  'violet',
  'amber',
  'ocean',
  'charcoal',
  'teal',
] as const

export type RandomCharacterTheme = typeof RANDOM_CHARACTER_THEMES[number]
type VerseIdentity = Pick<Verse, 'name' | 'slug'> | CharacterVerse | null | undefined

const normalizeVerseIdentity = (value: string | null | undefined) =>
  value?.trim().toLowerCase().replace(/[\s_]+/g, '-') ?? ''

export function isRandomVerse(verse: VerseIdentity): boolean {
  if (!verse) return false
  return normalizeVerseIdentity(verse.slug) === 'random' || normalizeVerseIdentity(verse.name) === 'random'
}

export function isRandomCharacter(character: Pick<Character, 'verses'>): boolean {
  return isRandomVerse(character.verses)
}

export function isOcSelectableVerse(verse: VerseIdentity): boolean {
  return Boolean(verse) && !isRandomVerse(verse)
}

function stableHash(value: string): number {
  let hash = 2166136261
  for (let index = 0; index < value.length; index += 1) {
    hash = Math.imul(hash ^ value.charCodeAt(index), 16777619)
  }
  return hash >>> 0
}

export function getRandomCharacterTheme(
  character: Pick<Character, 'id' | 'slug'>,
): RandomCharacterTheme {
  const stableIdentity = String(character.id || character.slug)
  return RANDOM_CHARACTER_THEMES[stableHash(stableIdentity) % RANDOM_CHARACTER_THEMES.length]
}
