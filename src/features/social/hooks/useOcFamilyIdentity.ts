import { useCallback, useEffect, useState } from 'react'
import { getMyOcFamilyIdentity, saveMyOcFamilyIdentity } from '../services/ocFamilyIdentity'
import type { OcFamilyIdentity, OcFamilyIdentityInput } from '../types'

function friendlyFamilyError(error: unknown): string {
  const message = error instanceof Error ? error.message
    : typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string' ? error.message
    : String(error)
  if (message.includes('40 characters')) return 'Family name cannot exceed 40 characters.'
  if (message.includes('100 characters')) return 'Family tagline cannot exceed 100 characters.'
  if (message.includes('750 characters')) return 'Family description cannot exceed 750 characters.'
  if (message.includes('logo object')) return 'The Family logo could not be verified. Choose the image again.'
  if (message.includes('unavailable for this profile')) return 'OC Family customization is unavailable for this profile.'
  return 'Unable to save your OC Family right now.'
}

export function useOcFamilyIdentity(ownerId: string, enabled: boolean) {
  const [identity, setIdentity] = useState<OcFamilyIdentity | null>(null)
  const [loading, setLoading] = useState(enabled)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (!enabled) {
      setIdentity(null)
      setLoading(false)
      setError(null)
      return
    }
    setLoading(true)
    try {
      setIdentity(await getMyOcFamilyIdentity())
      setError(null)
    } catch (loadError) {
      console.error('OC Family identity load failed', loadError)
      setError('Unable to load your OC Family identity.')
    } finally {
      setLoading(false)
    }
  }, [enabled])

  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  const save = async (input: OcFamilyIdentityInput): Promise<OcFamilyIdentity> => {
    setPending(true)
    try {
      const saved = await saveMyOcFamilyIdentity(ownerId, identity, input)
      setIdentity(saved)
      setError(null)
      return saved
    } catch (saveError) {
      console.error('OC Family identity save failed', saveError)
      throw new Error(friendlyFamilyError(saveError))
    } finally {
      setPending(false)
    }
  }

  return { identity, loading, pending, error, refresh, save }
}
