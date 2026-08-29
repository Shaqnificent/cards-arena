import { useCallback, useEffect, useRef, useState } from 'react'
import { equipOwnedBoon, getBoonCatalogue, getBoonDashboard, resolveBoonRoll, rollBoon, unequipOwnedBoon } from '../services/boons'
import type { BoonDashboard, BoonDefinition, BoonRollResult, PlayerBoon } from '../types'

function friendlyBoonError(cause: unknown): string {
  const message = typeof cause === 'object' && cause !== null && 'message' in cause && typeof cause.message === 'string'
    ? cause.message
    : cause instanceof Error ? cause.message : ''
  if (message.includes('already resolved')) return 'That Boon roll was already resolved. Your inventory has been refreshed.'
  if (message.includes('not owned') || message.includes('not found')) return 'That Boon is no longer available in your inventory.'
  if (message.includes('Not enough Boon Points')) return 'Not enough Boon Points.'
  if (message.includes('Resolve your current')) return 'Resolve your current Boon roll first.'
  if (message.includes('No new Boons')) return 'No new Boons are currently available.'
  if (message.includes('Choose a Boon to replace')) return 'Choose one of your owned Boons to replace.'
  if (message.includes('Sign in') || message.includes('Guests')) return 'Sign in with a persistent account to manage Boons.'
  if (message.includes('System profiles')) return 'System profiles cannot manage player Boons.'
  return 'Unable to update your Boon loadout. Try again.'
}

const emptyDashboard: BoonDashboard = {
  eligible: false,
  boonPoints: 0,
  rollCost: 0,
  canRoll: false,
  inventoryCount: 0,
  inventoryCapacity: 2,
  pendingRoll: null,
  boons: [],
}

export function useBoons(enabled: boolean) {
  const [dashboard, setDashboard] = useState<BoonDashboard>(emptyDashboard)
  const [catalogue, setCatalogue] = useState<BoonDefinition[]>([])
  const [loading, setLoading] = useState(enabled)
  const [error, setError] = useState<string | null>(null)
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [rolling, setRolling] = useState(false)
  const [resolvingId, setResolvingId] = useState<string | null>(null)
  const [rollResult, setRollResult] = useState<BoonRollResult | null>(null)
  const [pendingDecisionOpen, setPendingDecisionOpen] = useState(false)
  const rollRequestActive = useRef(false)

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
      if (nextDashboard.pendingRoll) setPendingDecisionOpen(true)
      setError(null)
    } catch (cause) {
      console.error('Boon dashboard load failed', cause)
      setError('Unable to load your Boons. Confirm the Phase 3 SQL is installed, then try again.')
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

  const roll = async () => {
    if (rollRequestActive.current || rolling || resolvingId || pendingId || dashboard.pendingRoll) return
    rollRequestActive.current = true
    setRolling(true)
    setError(null)
    try {
      const result = await rollBoon()
      setDashboard(result.dashboard)
      setRollResult(result)
      setPendingDecisionOpen(result.status === 'pending')
    } catch (cause) {
      console.error('Boon roll failed', cause)
      setError(friendlyBoonError(cause))
      if (typeof cause === 'object' && cause !== null && 'message' in cause && String(cause.message).includes('already')) await refresh()
    } finally {
      rollRequestActive.current = false
      setRolling(false)
    }
  }

  const resolve = async (action: 'replace' | 'discard', replaceId: string | null = null) => {
    const pendingRoll = dashboard.pendingRoll
    if (!pendingRoll || resolvingId || rolling || pendingId) return
    setResolvingId(action === 'discard' ? 'discard' : replaceId)
    setError(null)
    try {
      const result = await resolveBoonRoll(pendingRoll.id, action, replaceId)
      setDashboard(result.dashboard)
      setRollResult(null)
      setPendingDecisionOpen(false)
    } catch (cause) {
      console.error('Boon roll resolution failed', cause)
      setError(friendlyBoonError(cause))
      await refresh()
    } finally {
      setResolvingId(null)
    }
  }

  const closeReveal = () => setRollResult(null)
  const closePendingDecision = () => {
    setPendingDecisionOpen(false)
    setRollResult(null)
  }
  const openPendingDecision = () => setPendingDecisionOpen(true)

  return {
    dashboard,
    catalogue,
    loading,
    error,
    pendingId,
    rolling,
    resolvingId,
    rollResult,
    pendingDecisionOpen,
    refresh,
    equip,
    unequip,
    roll,
    resolve,
    closeReveal,
    closePendingDecision,
    openPendingDecision,
  }
}
