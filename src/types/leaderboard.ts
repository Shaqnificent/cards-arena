export interface LeaderboardPlayer {
  id: string
  username: string
  avatarUrl: string | null
  wins: number
  losses: number
  gamesPlayed: number
  winRate: number
  rank: number
}
