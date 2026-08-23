import type { Profile } from '../../types/profile'

export type MatchmakingState = 'checking' | 'idle' | 'joining' | 'searching' | 'matched' | 'cancelling' | 'error'
export type MatchStatus = 'waiting' | 'initiative' | 'oc_selection' | 'draft' | 'oc_preparation' | 'battle' | 'completed' | 'cancelled'

export interface MatchmakingRpcRow {
  result_status: 'waiting' | 'matched' | 'existing_match' | 'cancelled'
  match_id: string | null
}

export interface AdministratorMatchRpcRow {
  result_status: 'waiting' | 'matched' | 'administrator_matched' | 'existing_match'
  match_id: string | null
  retry_after_seconds: number
}

export interface QueueEntry {
  player_id: string
  status: 'waiting' | 'matched' | 'cancelled'
  joined_at: string
  matched_match_id: string | null
}

export interface MatchmakingController {
  status: MatchmakingState
  error: string | null
  queueJoinedAt: string | null
  claimingAdministrator: boolean
  administratorMatched: boolean
  findMatch: () => Promise<void>
  cancelSearch: (navigateIfMatched?: boolean) => Promise<void>
}

export interface OnlineMatch {
  id: string
  player_one_id: string
  player_two_id: string
  status: MatchStatus
  player_one_score: number
  player_two_score: number
  winner_id: string | null
  created_at: string
  started_at: string | null
  completed_at: string | null
}

export interface MatchWithPlayers extends OnlineMatch {
  player_one: Profile
  player_two: Profile
}
