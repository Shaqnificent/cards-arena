import type { Character } from '../../types/character'
import type { Profile, PublicGameProfile } from '../../types/profile'
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
  initiative_player_id: string | null
  initiative_resolved_at: string | null
  player_one: PublicGameProfile
  player_two: PublicGameProfile
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

export type OnlineDraftAction = 'bid' | 'pass' | 'fold' | 'oc-lock' | null
export type OcType = 'champion' | 'sacrificial'
export type OcPreparationDecision = 'none' | 'reserve' | 'absorb' | 'inactive' | 'sacrifice'
export interface OcPreparationFighter { matchCharacterId: string; characterId: number; name: string; verseId: number; verseName: string; overall: number; powerScore: number; tier: 'D' | 'C' | 'B' | 'A' | 'S' | 'LEGEND'; sacrificeBoost: number; compatibilityPercent?: number; effectiveBonus?: number; matchPowerScore?: number }
export interface MatchOcPreparationState {
  matchId: string; status: MatchStatus; yourPlayerId: string
  yourOC: { characterId: string; name: string; verseId: number; verseName: string; baseOverall: number; powerScore: number; ocType: OcType | null; imageUrl: string | null } | null
  eligibleSacrifices: OcPreparationFighter[]
  yourPreparation: { ocType: OcType | null; decision: OcPreparationDecision; ocSacrificed: boolean; sacrificedMatchCharacterId: string | null; sacrificeTier: string | null; sacrificeBoost: number; baseOverall: number | null; matchOverall: number | null; basePowerScore: number | null; baseTransferPower: number; recipientCount: number; lockedAt: string } | null
  yourLocked: boolean; opponentLocked: boolean; bothComplete: boolean
}
export type InitiativeChoice = 'rock' | 'paper' | 'scissors'
export interface OnlineInitiativeState {
  matchId: string
  status: MatchStatus
  initiativeRound: number
  initiativeState: 'choosing' | 'revealed'
  yourPlayerId: string
  opponentPlayerId: string
  yourProfile: PublicGameProfile
  opponentProfile: PublicGameProfile
  yourChoice: InitiativeChoice | null
  opponentLocked: boolean
  opponentChoice: InitiativeChoice | null
  winnerPlayerId: string | null
  isDraw: boolean
}
export interface MatchOcOption {
  characterId: string
  slot: number
  name: string
  verseId: number
  verseName: string
  overall: number
  powerScore: number
  overallCap: number
  imageUrl: string | null
  ocType: OcType | null
}
export type MatchOcProfile = Pick<Profile, 'id' | 'username' | 'avatar_url' | 'is_system_player'>
export interface MatchOcSelectionState {
  matchId: string
  status: MatchStatus
  yourPlayerId: string
  opponentPlayerId: string
  yourProfile: MatchOcProfile
  opponentProfile: MatchOcProfile
  yourOptions: MatchOcOption[]
  opponentOptions: MatchOcOption[]
  yourSelectedCharacterId: string | null
  yourLocked: boolean
  opponentLocked: boolean
  bothComplete: boolean
}
export type OnlineMatchLoadState = 'loading-match' | 'determining-initiative' | 'initiative' | 'initializing-oc-selection' | 'oc-selection' | 'initializing-draft' | 'loading-draft' | 'ready' | 'error'
