import type { CharacterVerse } from './verse'

export interface Character {
  id: number
  name: string
  slug: string
  version: string | null
  image_url: string | null
  overall: number
  power_score: number
  active: boolean
  verse_id: number
  verses: CharacterVerse | null
}
