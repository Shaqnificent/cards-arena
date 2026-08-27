import { usePlayerChallenges } from './playerChallengeContext'
import type { ChallengePlayerSummary } from './types'

export function ChallengeButton({ player, currentUserId, disabled = false }: { player: ChallengePlayerSummary; currentUserId: string; disabled?: boolean }) {
  const challenges = usePlayerChallenges()
  if (player.id === currentUserId || !challenges.eligible) return null

  const ownChallenge = challenges.challenge?.counterpart.id === player.id ? challenges.challenge : null
  const busy = Boolean(challenges.challenge && !ownChallenge)
  const sending = challenges.pendingAction === 'sending'
  const label = ownChallenge?.direction === 'outgoing' ? 'Challenge Sent' : ownChallenge || busy || disabled ? 'Player Busy' : sending ? 'Sending...' : 'Challenge'

  return <button
    type="button"
    className="player-challenge-button"
    disabled={disabled || busy || sending || Boolean(ownChallenge)}
    onClick={() => void challenges.send(player)}
  ><span aria-hidden="true">&#9876;</span><span className="challengeText">{label}</span></button>
}
