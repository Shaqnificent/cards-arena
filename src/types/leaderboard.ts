import type { AvatarMode } from './profile'

export interface LeaderboardPlayer {
  id: string
  username: string
  avatarUrl: string | null
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
  wins: number
  losses: number
  gamesPlayed: number
  winRate: number
  rank: number
  isSystemPlayer: boolean
}
