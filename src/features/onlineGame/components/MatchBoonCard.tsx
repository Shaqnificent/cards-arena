import type { MatchBoonSnapshot } from '../types'

interface MatchBoonCardProps {
  label: string
  boon: MatchBoonSnapshot | null
  revealed?: boolean
}

export function MatchBoonCard({ label, boon, revealed = true }: MatchBoonCardProps) {
  return <article className={`match-boon-card${boon ? ` rarity-${boon.rarity}` : ''}`}>
    <span className="match-boon-label">{label}</span>
    {!revealed ? <div className="match-boon-hidden"><strong>Hidden</strong><p>Reveals when the match begins.</p></div>
      : boon ? <div className="match-boon-details"><span aria-hidden="true">✦</span><div><span className={`boon-rarity ${boon.rarity}`}>{boon.rarity}</span><h2>{boon.name}</h2><p>{boon.description}</p></div></div>
        : <div className="match-boon-none"><strong>No Boon</strong><p>No tactical modifier was equipped.</p></div>}
  </article>
}
