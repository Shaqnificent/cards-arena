import { Link } from 'react-router-dom'
import type { LocalGameState } from '../types'
import { useState } from 'react'
import { usePlayerCharacters } from '../../ocs/hooks/usePlayerCharacters'
import { useOcProgression } from '../../ocs/hooks/useOcProgression'
import type { useLocalMatchProgression } from '../../ocs/hooks/useLocalMatchProgression'

interface MatchResultProps { state: LocalGameState; progression: ReturnType<typeof useLocalMatchProgression>; onRestart: () => void }

export function MatchResult({ state, progression, onRestart }: MatchResultProps) {
  const collection = usePlayerCharacters()
  const rewards = useOcProgression()
  const [targetId, setTargetId] = useState('')
  const [claimedName, setClaimedName] = useState<string | null>(null)
  const [claimError, setClaimError] = useState<string | null>(null)
  const title = state.winner === 'player' ? 'Victory' : state.winner === 'opponent' ? 'Defeat' : 'Draw'
  const activeCharacters = collection.characters.filter((character) => character.active)
  const rewardId = progression.result?.reward_id

  const claim = async () => {
    const character = activeCharacters.find((item) => item.id === (targetId || activeCharacters[0]?.id))
    if (!rewardId || !character) return setClaimError('Create an active OC before assigning progression.')
    setClaimError(null)
    try { await rewards.claim(rewardId, character.id); setClaimedName(character.name) }
    catch (error) { setClaimError(error instanceof Error ? error.message : 'Unable to assign progression.') }
  }
  return (
    <section className="match-result">
      <p className="eyebrow">Local Match Complete</p>
      <h1>{title}</h1>
      <div className="final-score"><span>You <b>{state.battle.playerScore}</b></span><i>—</i><span><b>{state.battle.opponentScore}</b> Opponent</span></div>
      <p>Local test matches do not affect your public record.</p>
      {state.winner === 'player' && <section className="match-progression"><p className="eyebrow">OC Progression</p>{progression.pending ? <p>Recording your eligible win...</p> : progression.error ? <p className="error-message" role="alert">{progression.error}</p> : claimedName ? <strong>+3 points added to {claimedName}</strong> : rewardId ? <><h2>+{progression.result?.points ?? 3} Points Earned</h2><p>Choose which active OC receives these points.</p><div><select aria-label="Choose progression recipient" value={targetId || activeCharacters[0]?.id || ''} onChange={(event) => setTargetId(event.target.value)} disabled={activeCharacters.length === 0}><option value="" disabled>Choose a fighter</option>{activeCharacters.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}</select><button className="button button-primary" disabled={activeCharacters.length === 0 || rewards.pendingKey !== null} onClick={() => void claim()}>Assign Points</button></div>{claimError && <p className="error-message" role="alert">{claimError}</p>}</> : <p>Win recorded. No progression reward is available.</p>}</section>}
      <div className="result-actions">
        <button className="button button-primary" onClick={onRestart}>Play Again</button>
        <Link className="button button-secondary" to="/">Return to Lobby</Link>
      </div>
    </section>
  )
}
