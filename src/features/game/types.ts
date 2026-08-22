import type { Character } from '../../types/character'

export type PlayerId = 'player' | 'opponent'
export type GamePhase = 'loading' | 'draft' | 'battle' | 'result'
export type DraftRoundState = 'decision' | 'bidding' | 'resolved'
export type MatchWinner = PlayerId | 'draw' | null

export interface GamePlayer {
  id: PlayerId
  name: string
  balance: number
  team: Character[]
}

export interface DraftState {
  roundState: DraftRoundState
  priority: PlayerId
  nextTiePriority: PlayerId
  turn: PlayerId
  currentBid: number | null
  leader: PlayerId | null
  proposedBid: number
  feedback: string | null
  aiThinking: boolean
}

export interface BattleReveal {
  playerCard: Character
  opponentCard: Character
  winner: PlayerId | 'tie'
}

export interface BattleState {
  round: number
  playerScore: number
  opponentScore: number
  selectedPlayerId: string | null
  playerUsedIds: string[]
  opponentUsedIds: string[]
  reveal: BattleReveal | null
}

export interface LocalGameState {
  phase: GamePhase
  pool: Character[]
  currentIndex: number
  player: GamePlayer
  opponent: GamePlayer
  draft: DraftState
  battle: BattleState
  winner: MatchWinner
  error: string | null
}
