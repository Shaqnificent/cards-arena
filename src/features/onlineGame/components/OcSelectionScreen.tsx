import { useState } from 'react'
import type { MatchOcOption, MatchOcSelectionState } from '../types'

const formatPower = (value: number) => value.toLocaleString()

function OcOptionCard({ option, selected, selectable, onSelect }: { option: MatchOcOption; selected?: boolean; selectable?: boolean; onSelect?: () => void }) {
  const content = <><div className="match-oc-avatar" aria-hidden="true">{option.name.charAt(0).toUpperCase()}</div><div className="match-oc-card-copy"><span>{option.verseName}</span><h3>{option.name}</h3><div><b>{option.overall} <small>OVR</small></b><b>{formatPower(option.powerScore)} <small>Power</small></b></div></div></>
  return selectable ? <button type="button" className={`match-oc-card${selected ? ' selected' : ''}`} onClick={onSelect}>{content}</button>
    : <article className="match-oc-card">{content}</article>
}

interface Props { state: MatchOcSelectionState; message: string | null; pending: boolean; onLock: (characterId: string) => Promise<void> }

export function OcSelectionScreen({ state, message, pending, onLock }: Props) {
  const [selectedId, setSelectedId] = useState(state.yourSelectedCharacterId ?? (state.yourOptions.length === 1 ? state.yourOptions[0]?.characterId ?? null : null))
  const ownSelection = state.yourOptions.find((option) => option.characterId === state.yourSelectedCharacterId)

  return <main className="oc-selection-page"><header className="game-header"><span className="brand-link">ANIME ARENA</span><span>Secret OC Selection</span><span className="nav-link">Match {state.matchId.slice(0, 8)}</span></header><section className="oc-selection-content">
    <div className="oc-selection-heading"><p className="eyebrow">Pre-Draft</p><h1>Choose Your OC</h1><p>Your opponent can see your possible OC Family, but your selected fighter stays hidden.</p></div>
    {message && <p className="online-draft-message" role="status">{message}</p>}
    <div className="oc-selection-layout"><section className="oc-selection-panel"><div className="oc-selection-panel-heading"><div><p className="eyebrow">Your OC Family</p><h2>{state.yourProfile.username}</h2></div>{state.yourLocked && <span>Locked In</span>}</div>
      {state.yourOptions.length === 0 ? <div className="match-oc-empty"><strong>No OC Family Equipped</strong><p>You will continue this match without an OC.</p></div> : state.yourLocked && ownSelection ? <><div className="match-oc-grid single"><OcOptionCard option={ownSelection} /></div><div className="oc-selection-waiting"><strong>OC Locked</strong><p>{state.opponentLocked ? 'Opponent locked. Preparing the draft...' : 'Waiting for opponent to choose their fighter...'}</p></div></> : <><div className="match-oc-grid">{state.yourOptions.map((option) => <OcOptionCard key={option.characterId} option={option} selectable selected={selectedId === option.characterId} onSelect={() => setSelectedId(option.characterId)} />)}</div><button className="button button-primary oc-selection-lock" disabled={!selectedId || pending} onClick={() => selectedId && void onLock(selectedId)}>{pending ? 'Locking...' : 'Lock In OC'}</button></>}
    </section><section className="oc-selection-panel opponent"><div className="oc-selection-panel-heading"><div><p className="eyebrow">Opponent OC Family</p><h2>{state.opponentProfile.username}</h2></div>{state.opponentLocked && <span>Selection Locked</span>}</div>
      {state.opponentOptions.length === 0 ? <div className="match-oc-empty"><strong>No OC Family Equipped</strong><p>Your opponent will continue without an OC.</p></div> : <div className="match-oc-grid">{state.opponentOptions.map((option) => <OcOptionCard key={option.characterId} option={option} />)}</div>}
      <div className="opponent-oc-secret"><span>Active OC</span><strong>???</strong><p>Their selection remains secret.</p></div>
    </section></div>
  </section></main>
}
