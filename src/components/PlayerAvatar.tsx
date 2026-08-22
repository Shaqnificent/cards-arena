import { useState } from 'react'

interface PlayerAvatarProps {
  username: string
  avatarUrl: string | null
  compact?: boolean
}

export function PlayerAvatar({ username, avatarUrl, compact = false }: PlayerAvatarProps) {
  const [imageFailed, setImageFailed] = useState(false)
  const className = `avatar${compact ? ' avatar-compact' : ''}`

  if (avatarUrl && !imageFailed) {
    return (
      <img
        className={className}
        src={avatarUrl}
        alt={`${username}'s avatar`}
        referrerPolicy="no-referrer"
        onError={() => setImageFailed(true)}
      />
    )
  }

  return (
    <div className={`${className} avatar-fallback`} aria-hidden="true">
      {username.charAt(0).toUpperCase() || '?'}
    </div>
  )
}
