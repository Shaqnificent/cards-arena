import { useCallback, useEffect, useState } from 'react'
import { getBoonDashboard } from '../../boons/services/boons'
import type { BoonDashboard } from '../../boons/types'
import { getEquippedPlayerCharacterSummary } from '../../ocs/services/playerCharacters'
import type { EquippedPlayerCharacterSummary } from '../../ocs/types'

export function useLoadoutSummary({ boonEligible, systemProfile }: { boonEligible: boolean; systemProfile: boolean }) {
  const [ocMembers, setOcMembers] = useState<EquippedPlayerCharacterSummary[]>([])
  const [boonDashboard, setBoonDashboard] = useState<BoonDashboard | null>(null)
  const [ocLoading, setOcLoading] = useState(!systemProfile)
  const [boonLoading, setBoonLoading] = useState(boonEligible)
  const [ocError, setOcError] = useState<string | null>(null)
  const [boonError, setBoonError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (systemProfile) {
      setOcLoading(false)
      setBoonLoading(false)
      return
    }

    setOcLoading(true)
    setBoonLoading(boonEligible)
    const [ocResult, boonResult] = await Promise.allSettled([
      getEquippedPlayerCharacterSummary(),
      boonEligible ? getBoonDashboard() : Promise.resolve(null),
    ])

    if (ocResult.status === 'fulfilled') {
      setOcMembers(ocResult.value)
      setOcError(null)
    } else {
      console.error('Loadout OC summary failed', ocResult.reason)
      setOcError('Unable to load your OC Family summary.')
    }

    if (boonResult.status === 'fulfilled') {
      setBoonDashboard(boonResult.value)
      setBoonError(null)
    } else {
      console.error('Loadout Boon summary failed', boonResult.reason)
      setBoonError('Unable to load your Boon summary.')
    }
    setOcLoading(false)
    setBoonLoading(false)
  }, [boonEligible, systemProfile])

  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  return { ocMembers, boonDashboard, ocLoading, boonLoading, ocError, boonError, refresh }
}
