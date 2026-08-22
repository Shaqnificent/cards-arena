import type { CharacterVerse } from './verse'

export interface Character {
  id: string
  name: string
  slug: string
  version: string | null
  image_url: string | null
  overall: number
  power_score: number
  active: boolean
  verse_id: string
  verses: CharacterVerse | null
}
