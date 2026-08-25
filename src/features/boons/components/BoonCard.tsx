import type { BoonDefinition, PlayerBoon } from '../types'

interface BoonCardProps {
  definition: BoonDefinition
  owned?: PlayerBoon
  pending?: boolean
  actionsDisabled?: boolean
  compact?: boolean
  summary?: boolean
  onEquip?: () => void
  onUnequip?: () => void
}

export function BoonCard({ definition, owned, pending = false, actionsDisabled = false, compact = false, summary = false, onEquip, onUnequip }: BoonCardProps) {
  const equipped = owned?.equipped ?? false
  if (summary) return <article className={`boon-equipped-summary rarity-${definition.rarity}`} aria-label={`${definition.name}, ${definition.rarity} Boon, equipped`}>
    <span className="boon-mark" aria-hidden="true">✦</span>
    <div><span className={`boon-rarity ${definition.rarity}`}>{definition.rarity}</span><h3>{definition.name}</h3></div>
    <strong className="boon-equipped-badge">✓ Equipped</strong>
  </article>

  return <article className={`boon-card rarity-${definition.rarity}${equipped ? ' equipped' : ''}${compact ? ' compact' : ''}`}>
    <header><span className={`boon-rarity ${definition.rarity}`}>{definition.rarity}</span>{equipped && <strong className="boon-equipped-badge">✓ Equipped</strong>}</header>
    <div className="boon-card-emblem" aria-hidden="true"><span className="boon-mark">✦</span></div>
    <div className="boon-card-body"><h3>{definition.name}</h3><p>{definition.description}</p></div>
    {owned && <footer><small>Owned {new Date(owned.acquiredAt).toLocaleDateString()}</small>{equipped
      ? <button type="button" className="button button-secondary" aria-pressed="true" disabled={actionsDisabled || pending} onClick={onUnequip}>{pending ? 'Unequipping...' : 'Unequip'}</button>
      : <button type="button" className="button button-primary" aria-pressed="false" disabled={actionsDisabled || pending} onClick={onEquip}>{pending ? 'Equipping...' : 'Equip'}</button>}</footer>}
  </article>
}
