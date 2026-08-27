import type { AvatarMode } from '../../types/profile'

export type PlayerChallengeStatus = 'pending' | 'accepted' | 'declined' | 'expired' | 'cancelled'
export type PlayerChallengeDirection = 'incoming' | 'outgoing'

export interface ChallengePlayerSummary {
  id: string
  username: string
  avatarUrl: string | null
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
}

export interface PlayerChallenge {
  id: string
  status: PlayerChallengeStatus
  direction: PlayerChallengeDirection
  challengerId: string
  challengedId: string
  createdAt: string
  expiresAt: string
  respondedAt: string | null
  matchId: string | null
  counterpart: ChallengePlayerSummary
}

export interface ChallengeMutationResult {
  status: PlayerChallengeStatus | 'unavailable'
  matchId: string | null
}

export interface PlayerChallengeContextValue {
  challenge: PlayerChallenge | null
  notice: string | null
  pendingAction: 'sending' | 'accepting' | 'declining' | 'cancelling' | null
  eligible: boolean
  send: (player: ChallengePlayerSummary) => Promise<void>
  accept: () => Promise<void>
  decline: () => Promise<void>
  cancel: () => Promise<void>
  clearNotice: () => void
}
