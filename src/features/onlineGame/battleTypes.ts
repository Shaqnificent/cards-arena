import type { Character } from '../../types/character'
import type { Profile } from '../../types/profile'

export type OnlineBattlePhase = 'selecting' | 'revealed' | 'complete'

export interface OnlineBattleFighter {
  id: string
  used: boolean
  character: Character
}

export interface OnlineBattleRound {
  roundNumber: number
  yourFighterId: string
  opponentFighterId: string
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
  yourProfile: Profile
  opponentProfile: Profile
  yourTeam: OnlineBattleFighter[]
  opponentTeam: OnlineBattleFighter[]
  yourSelectionId: string | null
  opponentLocked: boolean
  latestRound: OnlineBattleRound | null
}

export type OnlineBattleAction = 'lock' | 'advance' | null
