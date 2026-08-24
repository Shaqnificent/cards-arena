import type { BoonRoll, PlayerBoon } from '../types'
import { BoonCard } from './BoonCard'

interface BoonRollDialogProps {
  roll: BoonRoll
  mode: 'added' | 'pending'
  ownedBoons: PlayerBoon[]
  resolvingId: string | null
  onClose: () => void
  onReplace: (playerBoonId: string) => void
  onDiscard: () => void
}

export function BoonRollDialog({
  roll,
  mode,
  ownedBoons,
  resolvingId,
  onClose,
  onReplace,
  onDiscard,
}: BoonRollDialogProps) {
  const resolving = resolvingId !== null

  return <div className="oc-modal-backdrop boon-roll-backdrop" role="presentation">
    <section className={`oc-modal boon-roll-dialog rarity-${roll.definition.rarity}`} role="dialog" aria-modal="true" aria-labelledby="boon-roll-heading">
      <div className="oc-modal-heading">
        <div><p className="eyebrow">New Boon</p><h2 id="boon-roll-heading">{mode === 'pending' ? 'Choose what to keep' : 'Roll complete'}</h2></div>
        <button type="button" onClick={onClose} disabled={resolving} aria-label="Close Boon result">&times;</button>
      </div>

      <div className="boon-reveal-card">
        <span className="boon-reveal-spark" aria-hidden="true">✦</span>
        <span className={`boon-rarity ${roll.definition.rarity}`}>{roll.definition.rarity}</span>
        <h3>{roll.definition.name}</h3>
        <p>{roll.definition.description}</p>
      </div>

      {mode === 'added' ? <div className="boon-roll-added">
        <p>This Boon has been added to your inventory unequipped.</p>
        <button type="button" className="button button-primary" onClick={onClose}>View Inventory</button>
      </div> : <>
        <div className="boon-replacement-copy">
          <strong>Your inventory is full.</strong>
          <p>Choose one owned Boon to replace. Replacing an equipped Boon leaves your equipped slot empty.</p>
        </div>
        <div className="boon-replacement-grid">
          {ownedBoons.map((boon) => <div key={boon.id} className="boon-replacement-option">
            <BoonCard definition={boon.definition} owned={boon} compact actionsDisabled />
            <button
              type="button"
              className="button button-secondary"
              disabled={resolving}
              onClick={() => onReplace(boon.id)}
            >{resolvingId === boon.id ? 'Replacing...' : `Replace ${boon.definition.name}`}</button>
          </div>)}
        </div>
        <div className="boon-discard-action">
          <p>Discarding keeps both owned Boons. The {roll.cost.toLocaleString()} BP roll cost is not refunded.</p>
          <button type="button" className="button boon-discard-button" disabled={resolving} onClick={onDiscard}>
            {resolvingId === 'discard' ? 'Discarding...' : 'Discard New Boon'}
          </button>
        </div>
      </>}
    </section>
  </div>
}
