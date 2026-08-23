import { ADMINISTRATOR_QUOTES, type AdministratorQuoteContext } from '../data/administratorQuotes'

export type AdministratorResultQuoteContext = Exclude<AdministratorQuoteContext, 'match_start'>

interface AdministratorResultInput {
  administratorId: string
  humanPlayerId: string
  playerOneId: string
  playerTwoId: string
  playerOneScore: number
  playerTwoScore: number
  winnerId: string | null
}

export function getRandomAdministratorQuote(context: AdministratorQuoteContext): string | null {
  const pool = ADMINISTRATOR_QUOTES[context]
  if (!pool?.length) return null
  return pool[Math.floor(Math.random() * pool.length)] ?? null
}

export function getAdministratorResultQuoteContext({
  administratorId,
  humanPlayerId,
  playerOneId,
  playerTwoId,
  playerOneScore,
  playerTwoScore,
  winnerId,
}: AdministratorResultInput): AdministratorResultQuoteContext | null {
  if (![playerOneId, playerTwoId].includes(administratorId)
    || ![playerOneId, playerTwoId].includes(humanPlayerId)
    || administratorId === humanPlayerId) return null

  const administratorScore = administratorId === playerOneId ? playerOneScore : playerTwoScore
  const humanScore = humanPlayerId === playerOneId ? playerOneScore : playerTwoScore

  if (winnerId === null) return 'draw'
  if (winnerId === administratorId) {
    if (humanScore <= 0) return 'admin_sweep'
    if (humanScore === 1) return 'admin_clear_win'
    return 'admin_close_win'
  }
  if (winnerId === humanPlayerId) {
    if (administratorScore <= 0) return 'player_sweep'
    if (administratorScore === 1) return 'player_clear_win'
    return 'player_close_win'
  }
  return null
}
