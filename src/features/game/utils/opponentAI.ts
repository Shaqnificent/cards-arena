import type { Character } from '../../../types/character'

export function aiWantsToBid(character: Character, balance: number, slotsRemaining: number): boolean {
  if (balance === 0) return character.overall >= 94
  const chance = character.overall >= 95 ? 0.9 : character.overall >= 88 ? 0.6 : 0.28
  const urgency = slotsRemaining <= 2 ? 0.15 : 0
  return Math.random() < Math.min(1, chance + urgency)
}

export function aiMaximumBid(character: Character, balance: number, slotsRemaining: number): number {
  const ratingBudget = character.overall >= 97 ? 8 : character.overall >= 93 ? 6 : character.overall >= 88 ? 4 : 2
  const urgencyBonus = slotsRemaining <= 2 ? 2 : 0
  return Math.min(balance, ratingBudget + urgencyBonus)
}

export function chooseOpponentCard(team: Character[], usedIds: string[]): Character {
  const available = team.filter((character) => !usedIds.includes(character.id))
  if (available.length === 0) throw new Error('Opponent has no unused battle cards.')

  const sorted = [...available].sort((a, b) => b.power_score - a.power_score)
  const roll = Math.random()
  if (roll < 0.45) return sorted[0]
  if (roll < 0.7) return sorted[sorted.length - 1]
  return sorted[Math.floor(Math.random() * sorted.length)]
}
