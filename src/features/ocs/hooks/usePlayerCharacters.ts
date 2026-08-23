import { useCallback, useEffect, useState } from 'react'
import { createPlayerCharacter, getPlayerCharacters, retirePlayerCharacter, selectPlayerCharacterType, setPlayerCharacterEquipped } from '../services/playerCharacters'
import type { CreatePlayerCharacterInput, PlayerCharacter } from '../types'

function friendlyError(error: unknown, fallback: string): string {
  const message = error instanceof Error ? error.message
    : typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string' ? error.message
    : String(error)
  if (message.includes('already has 3 fighters')) return 'Your OC Family already has 3 fighters. Unequip one before adding another.'
  if (message.includes('already has 5 active fighters')) return 'Your OC collection is full. Retire one fighter before creating another.'
  if (message.includes('between 2 and 50')) return 'OC name must be between 2 and 50 characters.'
  if (message.includes('active verse')) return 'Select an active verse.'
  if (message.includes('not owned')) return 'That fighter is unavailable or does not belong to you.'
  return fallback
}

export function usePlayerCharacters() {
  const [characters, setCharacters] = useState<PlayerCharacter[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [pendingId, setPendingId] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    try { setCharacters(await getPlayerCharacters()); setError(null) }
    catch (loadError) { console.error('OC load failed', loadError); setError('Unable to load your OC family.') }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  const create = async (input: CreatePlayerCharacterInput) => {
    setPendingId('create')
    try { const created = await createPlayerCharacter(input); await refresh(); return created }
    catch (creationError) { console.error('OC creation failed', creationError); throw new Error(friendlyError(creationError, 'Unable to create your fighter.')) }
    finally { setPendingId(null) }
  }

  const setEquipped = async (character: PlayerCharacter) => {
    setPendingId(character.id)
    try { await setPlayerCharacterEquipped(character.id, !character.equipped); await refresh() }
    catch (equipError) { console.error('OC equip failed', equipError); throw new Error(friendlyError(equipError, 'Unable to update your OC Family.')) }
    finally { setPendingId(null) }
  }

  const retire = async (character: PlayerCharacter) => {
    setPendingId(character.id)
    try { await retirePlayerCharacter(character.id); await refresh() }
    catch (retirementError) { console.error('OC retirement failed', retirementError); throw new Error(friendlyError(retirementError, 'Unable to retire this fighter.')) }
    finally { setPendingId(null) }
  }

  const selectType = async (character: PlayerCharacter, ocType: PlayerCharacter['oc_type']) => {
    setPendingId(character.id)
    try { await selectPlayerCharacterType(character.id, ocType); await refresh() }
    catch (typeError) { console.error('OC type selection failed', typeError); throw new Error(friendlyError(typeError, 'Unable to set this fighter type.')) }
    finally { setPendingId(null) }
  }

  return { characters, loading, error, pendingId, refresh, create, setEquipped, retire, selectType }
}
