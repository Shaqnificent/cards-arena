import type { BoonDefinition, PlayerBoon } from '../types'

interface BoonCardProps {
  definition: BoonDefinition
  owned?: PlayerBoon
  pending?: boolean
  actionsDisabled?: boolean
  compact?: boolean
  onEquip?: () => void
  onUnequip?: () => void
}

export function BoonCard({ definition, owned, pending = false, actionsDisabled = false, compact = false, onEquip, onUnequip }: BoonCardProps) {
  const equipped = owned?.equipped ?? false
  if (owned) return <article className={`boon-owned-card rarity-${definition.rarity}${equipped ? ' equipped' : ''}`} aria-label={`${definition.name}, ${definition.rarity} Boon${equipped ? ', equipped' : ''}`}>
    <span className="boon-owned-mark" aria-hidden="true">✦</span>
    <div className="boon-owned-copy">
      <span className={`boon-rarity ${definition.rarity}`}>{definition.rarity}</span>
      <h3>{definition.name}</h3>
      {equipped && <strong className="boon-equipped-badge">✓ Equipped</strong>}
    </div>
    {equipped
      ? <button type="button" className="button button-secondary" aria-pressed="true" disabled={actionsDisabled || pending} onClick={onUnequip}>{pending ? 'Unequipping...' : 'Unequip'}</button>
      : <button type="button" className="button button-primary" aria-pressed="false" disabled={actionsDisabled || pending} onClick={onEquip}>{pending ? 'Equipping...' : 'Equip'}</button>}
  </article>

  return <article className={`boon-card rarity-${definition.rarity}${equipped ? ' equipped' : ''}${compact ? ' compact' : ''}`}>
    <header><span className={`boon-rarity ${definition.rarity}`}>{definition.rarity}</span>{equipped && <strong className="boon-equipped-badge">✓ Equipped</strong>}</header>
    <div className="boon-card-emblem" aria-hidden="true"><span className="boon-mark">✦</span></div>
    <div className="boon-card-body"><h3>{definition.name}</h3><p>{definition.description}</p></div>
  </article>
}
