export interface PublicOcFamilyMember {
  characterId: string
  slot: number
  name: string
  imageUrl: string | null
  lore: string | null
  verseId: number
  verseName: string
  verseSlug: string
  ocType: 'champion' | 'sacrificial'
  startingOverall: number
  overall: number
  overallCap: number
  powerScore: number
  powerScoreCap: number
  growth: number
}

export interface OcFamilyIdentity {
  name: string | null
  tagline: string | null
  description: string | null
  logoPath: string | null
  createdAt: string | null
  updatedAt: string | null
}

export interface OcFamilyIdentityInput {
  name: string
  tagline: string
  description: string
  logoFile: File | null
  removeLogo: boolean
}

export interface PublicOcFamily {
  name: string | null
  tagline: string | null
  description: string | null
  logoPath: string | null
  updatedAt: string | null
  members: PublicOcFamilyMember[]
}

export interface PublicPlayerProfile {
  playerId: string
  displayName: string
  avatarUrl: string | null
  wins: number
  losses: number
  winRate: number
  rank: number | null
  joinedAt: string
  ocFamily: PublicOcFamily
}
