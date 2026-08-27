import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { LeaderboardMode, LeaderboardPlayer } from '../types/leaderboard'

interface LeaderboardRpcRow {
  id: string
  username: string
  avatarUrl: LeaderboardPlayer['avatarUrl']
  avatarMode: LeaderboardPlayer['avatarMode']
  avatarBgColor: string
  avatarTextColor: string
  wins: number
  losses: number
  gamesPlayed: number
  winRate: number
  rank: number
  isSystemPlayer: boolean
}

interface LeaderboardState {
  players: LeaderboardPlayer[]
  loading: boolean
  error: string | null
  refresh: () => void
}

export function useLeaderboard(limit = 100, mode: LeaderboardMode = 'all'): LeaderboardState {
  const [requestVersion, setRequestVersion] = useState(0)
  const [state, setState] = useState<Omit<LeaderboardState, 'refresh'>>({ players: [], loading: true, error: null })

  useEffect(() => {
    let isCurrent = true

    const loadLeaderboard = async () => {
      setState((current) => ({ ...current, loading: true, error: null }))
      const { data, error } = await supabase.rpc('get_player_leaderboard', {
        p_mode: mode,
        p_limit: Math.min(100, Math.max(1, limit)),
      })

      if (!isCurrent) return

      if (error) {
        setState({ players: [], loading: false, error: error.message })
        return
      }

      const rankedPlayers = (Array.isArray(data) ? data : []) as LeaderboardRpcRow[]

      setState({ players: rankedPlayers, loading: false, error: null })
    }

    void loadLeaderboard()
    return () => { isCurrent = false }
  }, [limit, mode, requestVersion])

  return { ...state, refresh: () => setRequestVersion((version) => version + 1) }
}
