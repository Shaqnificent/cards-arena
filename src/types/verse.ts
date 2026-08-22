export interface Verse {
  id: string
  name: string
  slug: string
  image_url: string | null
  active: boolean
}

export type CharacterVerse = Pick<Verse, 'id' | 'name' | 'slug'>
