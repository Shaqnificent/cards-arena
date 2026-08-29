import { Component, Suspense, lazy, useEffect, useState, type ErrorInfo, type ReactNode } from 'react'
import type { BoonRoll, PlayerBoon } from '../types'
import { BoonCard } from './BoonCard'

const BoonRevealScene = lazy(() => import('./BoonRevealScene'))
const REVEAL_DURATION_MS = 1650

interface BoonRollDialogProps {
  roll: BoonRoll | null
  mode: 'added' | 'pending'
  animateReveal: boolean
  ownedBoons: PlayerBoon[]
  resolvingId: string | null
  onClose: () => void
  onReplace: (playerBoonId: string) => void
  onDiscard: () => void
}

function supportsWebGL(): boolean {
  if (typeof document === 'undefined') return false
  try {
    const canvas = document.createElement('canvas')
    const context = canvas.getContext('webgl2') ?? canvas.getContext('webgl')
    if (!context) return false
    context.getExtension('WEBGL_lose_context')?.loseContext()
    return true
  } catch {
    return false
  }
}

function useReducedMotion() {
  const [reduced, setReduced] = useState(() => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => setReduced(query.matches)
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  }, [])
  return reduced
}

function SceneFallback({ rarity }: { rarity: BoonRoll['definition']['rarity'] | null }) {
  return <div className={`boon-scene-fallback rarity-${rarity ?? 'epic'}`} aria-hidden="true"><span className="boon-fallback-ring" /><span className="boon-fallback-card"><i>✦</i></span></div>
}

class SceneErrorBoundary extends Component<{ fallback: ReactNode; children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error('Boon reveal WebGL scene failed', error, info) }
  render() { return this.state.failed ? this.props.fallback : this.props.children }
}

function BoonRevealDetails({ roll }: { roll: BoonRoll }) {
  return <div className="boon-reveal-card" role="status" aria-live="polite"><span className="boon-reveal-spark" aria-hidden="true">✦</span><span className={`boon-rarity ${roll.definition.rarity}`}>{roll.definition.rarity}</span><h3>{roll.definition.name}</h3><p>{roll.definition.description}</p></div>
}

export function BoonRollDialog({ roll, mode, animateReveal, ownedBoons, resolvingId, onClose, onReplace, onDiscard }: BoonRollDialogProps) {
  const reducedMotion = useReducedMotion()
  const [webGLAvailable] = useState(supportsWebGL)
  const [revealedRollId, setRevealedRollId] = useState<string | null>(null)
  const resolving = resolvingId !== null
  const rarity = roll?.definition.rarity ?? null
  const detailsVisible = Boolean(roll) && (!animateReveal || reducedMotion || revealedRollId === roll?.id)

  useEffect(() => {
    if (!roll || !animateReveal || reducedMotion) return
    const timer = window.setTimeout(() => setRevealedRollId(roll.id), REVEAL_DURATION_MS)
    return () => window.clearTimeout(timer)
  }, [animateReveal, reducedMotion, roll])

  return <div className="oc-modal-backdrop boon-roll-backdrop" role="presentation">
    <section className={`oc-modal boon-roll-dialog rarity-${rarity ?? 'rolling'}${detailsVisible ? ' details-visible' : ' scene-visible'}`} role="dialog" aria-modal="true" aria-labelledby="boon-roll-heading" aria-busy={!detailsVisible}>
      <div className="oc-modal-heading boon-roll-heading"><div><p className="eyebrow">{detailsVisible ? 'New Boon' : roll ? 'Boon Found' : 'Rolling Boon'}</p><h2 id="boon-roll-heading">{detailsVisible ? mode === 'pending' ? 'Choose what to keep' : 'Roll complete' : roll ? 'Revealing your Boon...' : 'The runes are deciding...'}</h2></div>{detailsVisible && <button type="button" onClick={onClose} disabled={resolving} aria-label="Close Boon result">&times;</button>}</div>

      {!detailsVisible ? <div className="boon-reveal-stage" aria-label={roll ? 'Revealing rolled Boon' : 'Rolling a Boon'}>
        {!reducedMotion && webGLAvailable ? <SceneErrorBoundary fallback={<SceneFallback rarity={rarity} />}><Suspense fallback={<SceneFallback rarity={rarity} />}><BoonRevealScene rarity={rarity} revealed={Boolean(roll)} /></Suspense></SceneErrorBoundary> : <SceneFallback rarity={rarity} />}
        <p>{roll ? `${roll.definition.rarity} energy detected` : 'Drawing from the active Boon pool'}</p>
      </div> : roll && <>
        <BoonRevealDetails roll={roll} />
        {mode === 'added' ? <div className="boon-roll-added"><p>This Boon has been added to your inventory unequipped.</p><button type="button" className="button button-primary" onClick={onClose}>Continue</button></div> : <>
          <div className="boon-replacement-copy"><strong>Your inventory is full.</strong><p>Choose one owned Boon to replace. Replacing an equipped Boon leaves your equipped slot empty.</p></div>
          <div className="boon-replacement-grid">{ownedBoons.map((boon) => <div key={boon.id} className="boon-replacement-option"><BoonCard definition={boon.definition} owned={boon} compact actionsDisabled /><button type="button" className="button button-secondary" disabled={resolving} onClick={() => onReplace(boon.id)}>{resolvingId === boon.id ? 'Replacing...' : `Replace ${boon.definition.name}`}</button></div>)}</div>
          <div className="boon-discard-action"><p>Discarding keeps both owned Boons. The {roll.cost.toLocaleString()} BP roll cost is not refunded.</p><button type="button" className="button boon-discard-button" disabled={resolving} onClick={onDiscard}>{resolvingId === 'discard' ? 'Discarding...' : 'Discard New Boon'}</button></div>
        </>}
      </>}
    </section>
  </div>
}
