import type { CharacterVerse } from '../../types/verse'

export type OcType = 'champion' | 'sacrificial'

export interface PlayerCharacter {
  id: string
  owner_id: string
  verse_id: number
  name: string
  image_url: string | null
  lore: string | null
  starting_overall: number
  overall: number
  overall_cap: number
  starting_power_score: number
  power_score: number
  power_score_cap: number
  progression_points: number
  equipped: boolean
  active: boolean
  created_at: string
  updated_at: string
  retired_at: string | null
  oc_type: OcType
  type_selected_at: string | null
  verse: CharacterVerse
}

export interface CreatePlayerCharacterInput {
  name: string
  verse: CharacterVerse
  ocType: OcType
}

export interface OcProgressionReward {
  id: string
  owner_id: string
  source_match_id: string
  points: number
  claimed_character_id: string | null
  claimed_at: string | null
  created_at: string
}

export interface LocalProgressionResult {
  result_status: 'reward_created' | 'completed_no_reward' | 'already_completed'
  reward_id: string | null
  points: number
}

export function getOverallUpgradeCost(currentOverall: number): number {
  if (currentOverall < 70) return 1
  if (currentOverall < 80) return 2
  if (currentOverall < 90) return 3
  return 4
}

export function getGrowthType(startingOverall: number): string {
  if (startingOverall <= 52) return 'High Potential'
  if (startingOverall <= 55) return 'Growth-Focused'
  if (startingOverall <= 58) return 'Balanced'
  return 'Prodigy'
}
