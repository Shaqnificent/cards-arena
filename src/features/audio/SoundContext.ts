import { createContext, useContext } from 'react'

export interface SoundPreference { enabled: boolean; toggle: () => void }

export const SoundContext = createContext<SoundPreference | null>(null)

export function useSoundPreference() {
  const value = useContext(SoundContext)
  if (!value) throw new Error('SoundProvider is missing')
  return value
}
