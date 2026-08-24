import type { Character } from '../../types/character'
import type { Profile } from '../../types/profile'

export type OnlineBattlePhase = 'selecting' | 'revealed' | 'complete'
export type YourOnlineBattleProfile = Pick<Profile, 'id' | 'username' | 'wins' | 'losses' | 'is_system_player'>
export type OpponentOnlineBattleProfile = Pick<Profile, 'id' | 'username' | 'is_system_player'>

export interface BoonAdjustedBattleStats {
  baseOverall?: number
  preparationOverallBonus?: number
  boonOverallBonus?: number
  basePowerScore?: number
  preparationPowerBonus?: number
  boonPowerBonus?: number
  boonEnhanced?: boolean
}

export interface MatchBoonResolutionTarget {
  fighterType: 'canon' | 'oc'
  fighterId: string
  overallBonus: number
  powerBonus: number
}

export interface MatchBoonResolution {
  boonKey: string | null
  status: 'applied' | 'no_eligible_target' | 'no_boon'
  resolvedValue: number | null
  resolvedVerseId: number | null
  targets: MatchBoonResolutionTarget[]
}

export interface OnlineBattleFighter extends BoonAdjustedBattleStats {
  id: string
  used: boolean
  sacrificed?: boolean
  empowered?: boolean
  basePowerScore?: number
  matchPowerScore?: number
  powerBoost?: number
  character: Character
}
export interface OnlineBattleOc extends BoonAdjustedBattleStats { id: string; name: string; verseName: string; overall: number; powerScore: number; used: boolean; boost: number; ocType: 'champion' | 'sacrificial'; decision: 'reserve' | 'absorb' | 'inactive' | 'sacrifice'; imageUrl: string | null; sacrificeTier?: string | null; sacrificeBoost?: number; sacrificedName?: string | null; recipientCount?: number }
export interface BattleSelectionRef { type: 'canon' | 'oc'; id: string }
export interface ResolvedBattleFighter extends BoonAdjustedBattleStats { type: 'canon' | 'oc'; id: string; name: string; overall: number; powerScore: number; empowered?: boolean; powerBoost?: number }

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
  yourSupport: OnlineBattleOc | null
  opponentSupport: OnlineBattleOc | null
  yourSelection: BattleSelectionRef | null
  opponentLocked: boolean
  latestRound: OnlineBattleRound | null
  yourBoonResolution: MatchBoonResolution | null
  boonPointsEarned: number
  boonPointBalance: number
}

export type OnlineBattleAction = 'lock' | 'advance' | null
