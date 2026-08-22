import type { Character } from '../../types/character'
import type { Profile } from '../../types/profile'

export type OnlineBattlePhase = 'selecting' | 'revealed' | 'complete'
export type YourOnlineBattleProfile = Pick<Profile, 'id' | 'username' | 'wins' | 'losses'>
export type OpponentOnlineBattleProfile = Pick<Profile, 'id' | 'username'>

export interface OnlineBattleFighter {
  id: string
  used: boolean
  sacrificed?: boolean
  character: Character
}
export interface OnlineBattleOc { id: string; name: string; verseName: string; overall: number; powerScore: number; used: boolean; boost: number; decision: 'reserve' | 'sacrifice'; sacrificeTier?: string | null; sacrificeBoost?: number; sacrificedName?: string | null }
export interface BattleSelectionRef { type: 'canon' | 'oc'; id: string }
export interface ResolvedBattleFighter { type: 'canon' | 'oc'; id: string; name: string; overall: number; powerScore: number }

export interface OnlineBattleRound {
  roundNumber: number
  yourFighter: ResolvedBattleFighter
  opponentFighter: ResolvedBattleFighter
  winnerPlayerId: string | null
}

export interface OnlineBattleState {
  matchId: string
  status: 'battle' | 'completed'
  roundNumber: number
  battleState: OnlineBattlePhase
  yourPlayerId: string
  opponentPlayerId: string
  yourScore: number
  opponentScore: number
  matchWinnerId: string | null
  yourProfile: YourOnlineBattleProfile
  opponentProfile: OpponentOnlineBattleProfile
  yourTeam: OnlineBattleFighter[]
  opponentTeam: OnlineBattleFighter[]
  yourOC: OnlineBattleOc | null
  opponentOC: OnlineBattleOc | null
  yourSelection: BattleSelectionRef | null
  opponentLocked: boolean
  latestRound: OnlineBattleRound | null
}

export type OnlineBattleAction = 'lock' | 'advance' | null
