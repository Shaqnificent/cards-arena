export interface Verse {
  id: string
  name: string
  slug: string | null
  image_url: string | null
  active: boolean
}

export type CharacterVerse = Pick<Verse, 'id' | 'name' | 'slug'>
