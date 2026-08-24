export interface PublicOcFamilyMember {
  characterId: string
  slot: number
  name: string
  imageUrl: string | null
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

export interface PublicPlayerProfile {
  playerId: string
  displayName: string
  avatarUrl: string | null
  wins: number
  losses: number
  winRate: number
  rank: number | null
  joinedAt: string
  ocFamily: PublicOcFamilyMember[]
}
