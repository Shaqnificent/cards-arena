import { createContext, useContext } from 'react'
import type { PlayerChallengeContextValue } from './types'

export const PlayerChallengeContext = createContext<PlayerChallengeContextValue | null>(null)

export function usePlayerChallenges(): PlayerChallengeContextValue {
  const value = useContext(PlayerChallengeContext)
  if (!value) throw new Error('usePlayerChallenges must be used inside PlayerChallengeProvider')
  return value
}
