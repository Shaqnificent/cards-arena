import type { ActiveMatchBoonState } from '../../onlineGame/types'

export function ActiveMatchBoonLoading() {
  return <aside className="active-match-boon loading" aria-live="polite">
    <span className="spinner" />
    <div><small>Match Boon</small><strong>Checking active match...</strong><p>Restoring the authoritative snapshot.</p></div>
  </aside>
}

export function ActiveMatchBoonNotice({ activeMatch }: { activeMatch: ActiveMatchBoonState }) {
  const boon = activeMatch.boon
  return <aside className={`active-match-boon${boon ? ` rarity-${boon.rarity}` : ''}`} aria-label="Boon locked for active ranked match">
    <span aria-hidden="true">◆</span>
    <div><small>Match Boon</small><strong>{boon?.name ?? 'No Boon'}</strong><p>{boon ? `${boon.rarity} · Locked for current match` : 'No tactical modifier was equipped when this match began.'}</p></div>
  </aside>
}
