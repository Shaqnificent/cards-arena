import { supabase } from '../../../lib/supabase'
import type { CreatePlayerCharacterInput, PlayerCharacter } from '../types'

const playerCharacterSelection = `
  id, owner_id, verse_id, name, image_url,
  starting_overall, overall, overall_cap,
  starting_power_score, power_score, power_score_cap,
  progression_points, equipped, active, created_at, updated_at, retired_at, oc_type, type_selected_at,
  verse:verses (id, name, slug)
`

export async function getPlayerCharacters(): Promise<PlayerCharacter[]> {
  const { data, error } = await supabase
    .from('player_characters')
    .select(playerCharacterSelection)
    .order('created_at')
  if (error) throw error
  return (data ?? []) as unknown as PlayerCharacter[]
}

export async function createPlayerCharacter(input: CreatePlayerCharacterInput): Promise<PlayerCharacter> {
  const { data, error } = await supabase.rpc('create_player_character', {
    p_name: input.name,
    p_verse_id: input.verse.id,
    p_oc_type: input.ocType,
  })
  if (error) throw error
  return { ...(data as Omit<PlayerCharacter, 'verse'>), verse: input.verse }
}

export async function selectPlayerCharacterType(characterId: string, ocType: PlayerCharacter['oc_type']): Promise<void> {
  const { error } = await supabase.rpc('select_player_character_type', { p_character_id: characterId, p_oc_type: ocType })
  if (error) throw error
}

export async function setPlayerCharacterEquipped(characterId: string, equipped: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_player_character_equipped', {
    p_character_id: characterId,
    p_equipped: equipped,
  })
  if (error) throw error
}

export async function retirePlayerCharacter(characterId: string): Promise<void> {
  const { error } = await supabase.rpc('retire_player_character', { p_character_id: characterId })
  if (error) throw error
}
