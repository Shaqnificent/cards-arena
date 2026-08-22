import type { Character } from '../../../types/character'
import type { GamePlayer, PlayerId } from '../types'

export const STARTING_BALANCE = 20
export const TEAM_SIZE = 5
export const DRAFT_POOL_SIZE = 10

export function shuffleCharacters(characters: Character[]): Character[] {
  const shuffled = [...characters]
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1))
    ;[shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]]
  }
  return shuffled
}

export function getPriorityPlayer(
  playerBalance: number,
  opponentBalance: number,
  tiePriority: PlayerId,
): { priority: PlayerId; nextTiePriority: PlayerId } {
  if (playerBalance > opponentBalance) return { priority: 'player', nextTiePriority: tiePriority }
  if (opponentBalance > playerBalance) return { priority: 'opponent', nextTiePriority: tiePriority }
  return {
    priority: tiePriority,
    nextTiePriority: tiePriority === 'player' ? 'opponent' : 'player',
  }
}

export function awardCharacter(player: GamePlayer, character: Character, cost: number): GamePlayer {
  if (player.team.length >= TEAM_SIZE) throw new Error(`${player.name} already has a full roster.`)
  if (cost < 0 || cost > player.balance) throw new Error('Invalid character cost.')
  return { ...player, balance: player.balance - cost, team: [...player.team, character] }
}

export function isValidBid(bid: number, currentBid: number | null, balance: number): boolean {
  return Number.isInteger(bid) && bid >= 0 && bid <= balance && (currentBid === null || bid > currentBid)
}

export function getBattleWinner(playerCard: Character, opponentCard: Character): PlayerId | 'tie' {
  if (playerCard.power_score > opponentCard.power_score) return 'player'
  if (opponentCard.power_score > playerCard.power_score) return 'opponent'
  return 'tie'
}

export function isMatchWon(playerScore: number, opponentScore: number): boolean {
  return playerScore >= 3 || opponentScore >= 3
}
