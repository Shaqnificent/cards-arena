import type { CSSProperties } from 'react'
import type { AdministratorQuoteContext } from '../data/administratorQuotes'
import { PlayerAvatar } from './PlayerAvatar'
import { SystemBadge } from './SystemBadge'

export interface AdministratorToastMessage {
  context: AdministratorQuoteContext
  quote: string
  username: string
  avatarUrl: string | null
  durationMs: number
}

export function AdministratorToast({ message }: { message: AdministratorToastMessage }) {
  const style = { '--administrator-toast-duration': `${message.durationMs}ms` } as CSSProperties
  return <aside className="administrator-toast" style={style} role="status" aria-live="polite" aria-atomic="true">
    <PlayerAvatar compact username={message.username} avatarUrl={message.avatarUrl} />
    <div>
      <header><strong>{message.username}</strong><SystemBadge /></header>
      <blockquote>“{message.quote}”</blockquote>
    </div>
  </aside>
}
