export type BoonRarity = 'common' | 'rare' | 'epic' | 'legendary' | 'mythic'

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

export type BoonRollStatus = 'pending' | 'kept' | 'discarded'

export interface BoonRoll {
  id: string
  cost: number
  status: BoonRollStatus
  createdAt: string
  definition: BoonDefinition
}

export interface BoonDashboard {
  eligible: boolean
  boonPoints: number
  rollCost: number
  canRoll: boolean
  inventoryCount: number
  inventoryCapacity: 2
  pendingRoll: BoonRoll | null
  boons: PlayerBoon[]
}

export interface BoonRollResult {
  status: 'added' | 'pending'
  boonPoints: number
  roll: BoonRoll
  dashboard: BoonDashboard
}

export interface BoonRollResolution {
  status: 'replaced' | 'discarded'
  dashboard: BoonDashboard
}
