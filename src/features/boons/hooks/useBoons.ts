import { useCallback, useEffect, useState } from 'react'
import { equipOwnedBoon, getBoonCatalogue, getBoonDashboard, unequipOwnedBoon } from '../services/boons'
import type { BoonDashboard, BoonDefinition, PlayerBoon } from '../types'

function friendlyBoonError(cause: unknown): string {
  const message = typeof cause === 'object' && cause !== null && 'message' in cause && typeof cause.message === 'string'
    ? cause.message
    : cause instanceof Error ? cause.message : ''
  if (message.includes('not owned') || message.includes('not found')) return 'That Boon is no longer available in your inventory.'
  if (message.includes('Sign in') || message.includes('Guests')) return 'Sign in with a persistent account to manage Boons.'
  if (message.includes('System profiles')) return 'System profiles cannot manage player Boons.'
  return 'Unable to update your Boon loadout. Try again.'
}

const emptyDashboard: BoonDashboard = {
  eligible: false,
  boonPoints: 0,
  inventoryCount: 0,
  inventoryCapacity: 2,
  boons: [],
}

export function useBoons(enabled: boolean) {
  const [dashboard, setDashboard] = useState<BoonDashboard>(emptyDashboard)
  const [catalogue, setCatalogue] = useState<BoonDefinition[]>([])
  const [loading, setLoading] = useState(enabled)
  const [error, setError] = useState<string | null>(null)
  const [pendingId, setPendingId] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (!enabled) {
      setDashboard(emptyDashboard)
      setCatalogue([])
      setLoading(false)
      return
    }
    setLoading(true)
    try {
      const [nextDashboard, nextCatalogue] = await Promise.all([getBoonDashboard(), getBoonCatalogue()])
      setDashboard(nextDashboard)
      setCatalogue(nextCatalogue)
      setError(null)
    } catch (cause) {
      console.error('Boon dashboard load failed', cause)
      setError('Unable to load your Boons. Confirm the Phase 2 SQL is installed, then try again.')
    } finally {
      setLoading(false)
    }
  }, [enabled])

  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  const equip = async (boon: PlayerBoon) => {
    if (pendingId) return
    setPendingId(boon.id)
    setError(null)
    try { setDashboard(await equipOwnedBoon(boon.id)) }
    catch (cause) { console.error('Boon equip failed', cause); setError(friendlyBoonError(cause)) }
    finally { setPendingId(null) }
  }

  const unequip = async (boon: PlayerBoon) => {
    if (pendingId) return
    setPendingId(boon.id)
    setError(null)
    try { setDashboard(await unequipOwnedBoon()) }
    catch (cause) { console.error('Boon unequip failed', cause); setError(friendlyBoonError(cause)) }
    finally { setPendingId(null) }
  }

  return { dashboard, catalogue, loading, error, pendingId, refresh, equip, unequip }
}
