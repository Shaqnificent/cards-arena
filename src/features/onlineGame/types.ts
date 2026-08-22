import type { Character } from '../../types/character'
import type { Profile } from '../../types/profile'
import type { MatchStatus } from '../matchmaking/types'

export type OnlineDraftPhase = 'preparing' | 'decision' | 'bidding' | 'complete'

export interface OnlineMatchRecord {
  id: string
  player_one_id: string
  player_two_id: string
  status: MatchStatus
  current_draft_position: number
  draft_state: OnlineDraftPhase
  current_bid: number | null
  current_bidder_id: string | null
  priority_player_id: string | null
  tie_priority_player_id: string | null
  action_version: number
  player_one: Profile
  player_two: Profile
}

export interface OnlineMatchPlayer {
  id: string
  match_id: string
  player_id: string
  player_number: 1 | 2
  balance: number
}

export interface OnlineMatchCharacter {
  id: string
  match_id: string
  character_id: string
  draft_position: number
  owner_player_id: string | null
  purchase_price: number | null
  assigned_at: string | null
  character: Character
}

export interface OnlineDraftState {
  match: OnlineMatchRecord
  players: OnlineMatchPlayer[]
  revealedCharacters: OnlineMatchCharacter[]
  currentCharacter: OnlineMatchCharacter | null
}

export type OnlineDraftAction = 'bid' | 'pass' | 'fold' | null
export type OnlineMatchLoadState = 'loading-match' | 'initializing-draft' | 'loading-draft' | 'ready' | 'error'
