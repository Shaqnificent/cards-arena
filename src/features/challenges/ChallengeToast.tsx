import { useEffect, useState } from 'react'
import { PlayerAvatar } from '../../components/PlayerAvatar'
import { usePlayerChallenges } from './playerChallengeContext'

function remainingSeconds(expiresAt: string): number {
  return Math.max(0, Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 1000))
}

export function ChallengeToast() {
  const { challenge, notice, pendingAction, accept, decline, cancel, clearNotice } = usePlayerChallenges()
  const [remaining, setRemaining] = useState(challenge ? remainingSeconds(challenge.expiresAt) : 0)

  useEffect(() => {
    if (!challenge) return
    const update = () => setRemaining(remainingSeconds(challenge.expiresAt))
    update()
    const timer = window.setInterval(update, 1000)
    return () => window.clearInterval(timer)
  }, [challenge])

  if (!challenge && !notice) return null
  if (!challenge) return <aside className="challenge-notice" role="status"><span>{notice}</span><button type="button" onClick={clearNotice} aria-label="Dismiss">&times;</button></aside>

  const player = challenge.counterpart
  const incoming = challenge.direction === 'incoming'
  return <aside className="challenge-toast" role={incoming ? 'dialog' : 'status'} aria-label={incoming ? 'Challenge received' : 'Challenge sent'}>
    <div className="challenge-toast-heading">
      <PlayerAvatar compact username={player.username} avatarUrl={player.avatarUrl} avatarMode={player.avatarMode} avatarBgColor={player.avatarBgColor} avatarTextColor={player.avatarTextColor} />
      <div><small>{incoming ? 'Challenge Received' : 'Challenge Sent'}</small><strong>{player.username}</strong><span>Direct Challenge &middot; Unranked</span></div>
      <time>{remaining}s</time>
    </div>
    <p>{incoming ? `${player.username} wants to challenge you.` : 'Waiting for a response...'}</p>
    <div className="challenge-toast-actions">
      {incoming ? <><button type="button" disabled={Boolean(pendingAction)} onClick={() => void decline()}>Decline</button><button type="button" className="primary" disabled={Boolean(pendingAction)} onClick={() => void accept()}>{pendingAction === 'accepting' ? 'Accepting...' : 'Accept'}</button></>
        : <button type="button" disabled={Boolean(pendingAction)} onClick={() => void cancel()}>{pendingAction === 'cancelling' ? 'Cancelling...' : 'Cancel Challenge'}</button>}
    </div>
  </aside>
}
