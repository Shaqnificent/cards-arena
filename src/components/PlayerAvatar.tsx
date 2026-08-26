import { useState, type CSSProperties } from 'react'
import type { AvatarMode } from '../types/profile'

const supportedBackgrounds = new Set(['#151126', '#C92A5B', '#7C3AED', '#D61F7C', '#2563EB', '#0891B2', '#059669', '#B7791F', '#6B7280'])
const supportedForegrounds = new Set(['#FFFFFF', '#FBBF24', '#C4B5FD', '#F9A8D4', '#11111A'])

interface PlayerAvatarProps {
  username: string
  avatarUrl: string | null
  avatarMode?: AvatarMode
  avatarBgColor?: string
  avatarTextColor?: string
  compact?: boolean
}

export function PlayerAvatar({ username, avatarUrl, avatarMode = 'google', avatarBgColor, avatarTextColor, compact = false }: PlayerAvatarProps) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null)
  const className = `avatar${compact ? ' avatar-compact' : ''}`
  const background = normalizeColor(avatarBgColor, supportedBackgrounds, '#7C3AED')
  const foreground = normalizeColor(avatarTextColor, supportedForegrounds, '#FFFFFF')

  if (avatarMode === 'google' && avatarUrl && avatarUrl !== failedUrl) {
    return (
      <img
        className={className}
        src={avatarUrl}
        alt={`${username}'s avatar`}
        referrerPolicy="no-referrer"
        onError={() => setFailedUrl(avatarUrl)}
      />
    )
  }

  return (
    <div className={`${className} avatar-fallback`} style={{ '--avatar-bg': background, '--avatar-text': foreground } as CSSProperties} aria-label={`${username}'s initial avatar`} role="img">
      {username.charAt(0).toUpperCase() || '?'}
    </div>
  )
}

function normalizeColor(value: string | undefined, supported: Set<string>, fallback: string) {
  const normalized = value?.toUpperCase()
  return normalized && supported.has(normalized) ? normalized : fallback
}
