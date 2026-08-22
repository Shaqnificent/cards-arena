import { useMemo, useState, type ReactNode } from 'react'
import { SFX_STORAGE_KEY } from './gameSounds'
import { SoundContext } from './SoundContext'

export function SoundProvider({ children }: { children: ReactNode }) {
  const [enabled, setEnabled] = useState(() => localStorage.getItem(SFX_STORAGE_KEY) !== 'false')
  const value = useMemo(() => ({ enabled, toggle: () => setEnabled((current) => { const next = !current; localStorage.setItem(SFX_STORAGE_KEY, String(next)); return next }) }), [enabled])
  return <SoundContext.Provider value={value}>{children}</SoundContext.Provider>
}
