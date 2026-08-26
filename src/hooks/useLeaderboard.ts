import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { LeaderboardPlayer } from '../types/leaderboard'
import type { AvatarMode } from '../types/profile'

interface LeaderboardProfileRow {
  id: string
  username: string
  avatar_url: string | null
  avatar_mode: AvatarMode
  avatar_bg_color: string
  avatar_text_color: string
  is_guest: boolean
  is_system_player: boolean
  wins: number
  losses: number
}

interface LeaderboardState {
  players: LeaderboardPlayer[]
  loading: boolean
  error: string | null
}

export function useLeaderboard(limit = 100): LeaderboardState {
  const [state, setState] = useState<LeaderboardState>({ players: [], loading: true, error: null })

  useEffect(() => {
    let isCurrent = true

    const loadLeaderboard = async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, avatar_url, avatar_mode, avatar_bg_color, avatar_text_color, is_guest, is_system_player, wins, losses')
        .eq('is_guest', false)

      if (!isCurrent) return

      if (error) {
        setState({ players: [], loading: false, error: error.message })
        return
      }

      const rankedPlayers = ((data ?? []) as LeaderboardProfileRow[])
        .map((profile) => {
          const gamesPlayed = profile.wins + profile.losses
          return {
            id: profile.id,
            username: profile.username,
            avatarUrl: profile.avatar_url,
            avatarMode: profile.avatar_mode,
            avatarBgColor: profile.avatar_bg_color,
            avatarTextColor: profile.avatar_text_color,
            wins: profile.wins,
            losses: profile.losses,
            gamesPlayed,
            winRate: gamesPlayed === 0 ? 0 : (profile.wins / gamesPlayed) * 100,
            isSystemPlayer: profile.is_system_player,
          }
        })
        .filter((player) => player.gamesPlayed > 0)
        .sort((a, b) =>
          b.winRate - a.winRate ||
          b.wins - a.wins ||
          b.gamesPlayed - a.gamesPlayed ||
          a.username.localeCompare(b.username) ||
          a.id.localeCompare(b.id),
        )
        .map((player, index) => ({ ...player, rank: index + 1 }))
        .slice(0, Math.max(0, limit))

      setState({ players: rankedPlayers, loading: false, error: null })
    }

    void loadLeaderboard()
    return () => { isCurrent = false }
  }, [limit])

  return state
}
