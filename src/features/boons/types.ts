export type BoonRarity = 'common' | 'rare' | 'epic' | 'legendary'

export interface BoonDefinition {
  id: string
  key: string
  name: string
  description: string
  rarity: BoonRarity
  effectType: string
  effectValue: number | null
  targetRule: string
}

export interface PlayerBoon {
  id: string
  equipped: boolean
  acquiredAt: string
  definition: BoonDefinition
}

export interface BoonDashboard {
  eligible: boolean
  boonPoints: number
  inventoryCount: number
  inventoryCapacity: 2
  boons: PlayerBoon[]
}
