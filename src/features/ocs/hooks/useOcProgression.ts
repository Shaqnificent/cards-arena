import { useCallback, useEffect, useState } from 'react'
import { claimProgressionReward, getUnclaimedProgressionRewards, upgradeOverall, upgradePower } from '../services/progression'
import type { OcProgressionReward, PlayerCharacter } from '../types'

function progressionError(error: unknown, fallback: string): string {
  const message = typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string' ? error.message : ''
  if (message.includes('Not enough progression')) return 'This fighter does not have enough progression points.'
  if (message.includes('already at its cap')) return message
  if (message.includes('already been claimed')) return 'That reward has already been claimed.'
  if (message.includes('not owned')) return 'That reward or fighter is unavailable.'
  return fallback
}

export function useOcProgression() {
  const [rewards, setRewards] = useState<OcProgressionReward[]>([])
  const [loading, setLoading] = useState(true)
  const [pendingKey, setPendingKey] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const refreshRewards = useCallback(async () => {
    try { setRewards(await getUnclaimedProgressionRewards()); setError(null) }
    catch (loadError) { console.error('OC reward load failed', loadError); setError('Unable to load progression rewards.') }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { void Promise.resolve().then(refreshRewards) }, [refreshRewards])

  const claim = async (rewardId: string, characterId: string) => {
    setPendingKey(`claim:${rewardId}`); setError(null)
    try { const updated = await claimProgressionReward(rewardId, characterId); await refreshRewards(); return updated }
    catch (claimError) { console.error('OC reward claim failed', claimError); throw new Error(progressionError(claimError, 'Unable to assign this progression reward.')) }
    finally { setPendingKey(null) }
  }

  const upgrade = async (character: PlayerCharacter, stat: 'overall' | 'power') => {
    setPendingKey(`${stat}:${character.id}`); setError(null)
    try { return stat === 'overall' ? await upgradeOverall(character.id) : await upgradePower(character.id) }
    catch (upgradeError) { console.error('OC upgrade failed', upgradeError); throw new Error(progressionError(upgradeError, 'Unable to develop this fighter.')) }
    finally { setPendingKey(null) }
  }

  return { rewards, loading, pendingKey, error, refreshRewards, claim, upgrade }
}
