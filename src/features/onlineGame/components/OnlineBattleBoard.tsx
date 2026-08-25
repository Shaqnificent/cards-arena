import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { GameCard } from '../../game/components/GameCard'
import type { OnlineBattleAction, OnlineBattleState, ResolvedBattleFighter } from '../battleTypes'
import { resolveOcImageSrc } from '../../ocs/services/ocImageUrl'
import { useGameSounds } from '../../audio/useGameSounds'
import { SystemBadge } from '../../../components/SystemBadge'
import { CharacterArtwork } from '../../../components/CharacterArtwork'
import type { Character } from '../../../types/character'

interface Props {
  state: OnlineBattleState
  pendingAction: OnlineBattleAction
  message: string | null
  onLock: (selectionType: 'canon' | 'oc', fighterId: string) => Promise<void>
  onAdvance: () => Promise<void>
  onFinalResultVisible?: () => void
}

function boonBonusText(fighter: Pick<ResolvedBattleFighter, 'boonOverallBonus' | 'boonPowerBonus'>) {
  const bonuses = []
  if (fighter.boonOverallBonus) bonuses.push(`${fighter.boonOverallBonus > 0 ? '+' : ''}${fighter.boonOverallBonus} OVR`)
  if (fighter.boonPowerBonus) bonuses.push(`${fighter.boonPowerBonus > 0 ? '+' : ''}${fighter.boonPowerBonus.toLocaleString()} Power`)
  return bonuses.join(' · ')
}

function hasBoonEffect(fighter: Pick<ResolvedBattleFighter, 'boonOverallBonus' | 'boonPowerBonus'>) {
  return Boolean(fighter.boonOverallBonus || fighter.boonPowerBonus)
}

function signedValue(value: number) {
  return `${value > 0 ? '+' : ''}${value.toLocaleString()}`
}

function boonBreakdownTitle(fighter: ResolvedBattleFighter) {
  return [
    fighter.baseOverall != null ? `OVR: Base ${fighter.baseOverall}` : null,
    fighter.preparationOverallBonus ? `Prep +${fighter.preparationOverallBonus}` : null,
    fighter.boonOverallBonus ? `Boon ${signedValue(fighter.boonOverallBonus)}` : null,
    fighter.basePowerScore != null ? `Power: Base ${fighter.basePowerScore.toLocaleString()}` : null,
    fighter.preparationPowerBonus ? `Prep +${fighter.preparationPowerBonus.toLocaleString()}` : null,
    fighter.boonPowerBonus ? `Boon ${signedValue(fighter.boonPowerBonus)}` : null,
  ].filter(Boolean).join(' · ')
}

function ResolvedCard({ fighter, character, oc, imageUrl, side, winner }: { fighter: ResolvedBattleFighter; character?: Character; oc?: OnlineBattleState['opponentOC']; imageUrl?: string | null; side: 'player' | 'opponent'; winner: boolean }) {
  const resolvedImageUrl = fighter.type === 'oc' ? resolveOcImageSrc(imageUrl) : imageUrl
  return <article className={`result-fighter-card ${side}${winner ? ' winner' : ''}`}>
    <div className="result-fighter-media">
      {fighter.type === 'canon' && character
        ? <CharacterArtwork character={character} imageClassName="result-fighter-image" fallbackClassName="result-fighter-fallback" />
        : resolvedImageUrl
          ? <img src={resolvedImageUrl} alt="" />
          : <span className="result-fighter-fallback" aria-hidden="true">{fighter.name.charAt(0)}</span>}
      {fighter.type === 'oc' && <small className="oc-reveal-badge">OC Revealed</small>}
    </div>
    <div className="result-fighter-body">
      <strong>{fighter.name}</strong>
      <div className="result-fighter-stat"><i aria-hidden="true">◇</i><b>{fighter.overall} OVR</b></div>
      <div className="result-fighter-stat"><i aria-hidden="true">ϟ</i><span>{fighter.powerScore.toLocaleString()} Power</span></div>
      {fighter.empowered && <div className="result-empowered"><b>Empowered</b><span>+{fighter.powerBoost?.toLocaleString()} Power</span></div>}
      {hasBoonEffect(fighter) && <div className="result-boon-effect" title={boonBreakdownTitle(fighter)}><b>Boon</b><span>{boonBonusText(fighter)}</span></div>}
      {fighter.type === 'oc' && (oc?.decision === 'absorb'
        ? <div className="result-sacrifice"><small>Absorbed</small><b>{oc.sacrificedName}</b><span>{oc.sacrificeTier} Tier · +{oc.sacrificeBoost} OVR</span></div>
        : <em className="result-no-sacrifice">No Sacrifice</em>)}
    </div>
  </article>
}

export function OnlineBattleBoard({ state, pendingAction, message, onLock, onAdvance, onFinalResultVisible }: Props) {
  const [selection, setSelection] = useState<{ type: 'canon' | 'oc'; id: string } | null>(null)
  const [showFinalResult, setShowFinalResult] = useState(false)
  const sounds = useGameSounds()
  const lockSeen = useRef(Boolean(state.yourSelection))
  const soundedRound = useRef<number | null>(null)
  const battleHandRef = useRef<HTMLDivElement | null>(null)
  const yourSelection = state.yourSelection
  const revealed = state.battleState !== 'selecting' ? state.latestRound : null
  const victory = state.matchWinnerId === state.yourPlayerId
  const draw = state.status === 'completed' && !state.matchWinnerId
  const roundWinner = revealed?.winnerPlayerId === state.yourPlayerId ? 'player' : revealed?.winnerPlayerId === state.opponentPlayerId ? 'opponent' : 'draw'
  const yourRevealedCharacter = revealed?.yourFighter.type === 'canon' ? state.yourTeam.find((item) => item.id === revealed.yourFighter.id)?.character : undefined
  const opponentRevealedCharacter = revealed?.opponentFighter.type === 'canon' ? state.opponentTeam.find((item) => item.id === revealed.opponentFighter.id)?.character : undefined
  const yourImage = revealed?.yourFighter.type === 'oc' ? state.yourOC?.imageUrl : yourRevealedCharacter?.image_url
  const opponentImage = revealed?.opponentFighter.type === 'oc' ? state.opponentOC?.imageUrl : opponentRevealedCharacter?.image_url
  const finalRound = state.status === 'completed' || state.battleState === 'complete'
  const finalResultVisible = state.status === 'completed' && (showFinalResult || !revealed)

  useEffect(() => {
    if (!lockSeen.current && state.yourSelection) sounds.playLockIn()
    lockSeen.current = Boolean(state.yourSelection)
  }, [sounds, state.yourSelection])

  useEffect(() => {
    if (!revealed || soundedRound.current === revealed.roundNumber) return
    soundedRound.current = revealed.roundNumber
    sounds.playRoundReveal()
    const timer = window.setTimeout(() => {
      if (revealed.winnerPlayerId === state.yourPlayerId) sounds.playRoundWin()
      else if (revealed.winnerPlayerId === state.opponentPlayerId) sounds.playRoundLose()
      else sounds.playRoundDraw()
    }, 180)
    return () => window.clearTimeout(timer)
  }, [revealed, sounds, state.opponentPlayerId, state.yourPlayerId])

  useEffect(() => {
    if (finalResultVisible) onFinalResultVisible?.()
  }, [finalResultVisible, onFinalResultVisible])

  useEffect(() => {
    if (!window.matchMedia('(max-width: 600px)').matches) return
    const selectedCanonId = selection?.type === 'canon' ? selection.id : yourSelection?.type === 'canon' ? yourSelection.id : null
    const centerId = selectedCanonId ?? state.yourTeam[Math.floor(state.yourTeam.length / 2)]?.id
    battleHandRef.current?.querySelector<HTMLElement>(`[data-fighter-id="${centerId}"]`)?.scrollIntoView({
      behavior: selectedCanonId ? 'smooth' : 'auto',
      block: 'nearest',
      inline: 'center',
    })
  }, [selection, state.yourTeam, yourSelection])

  const selectFighter = (type: 'canon' | 'oc', id: string) => {
    if (selection?.type === type && selection.id === id) return
    setSelection({ type, id })
    sounds.playCardSelect()
  }

  if (finalResultVisible) {
    return <section className="match-result">
      <p className="eyebrow">Match Complete</p><h1>{draw ? 'Draw' : victory ? 'Victory' : 'Defeat'}</h1>
      <div className="final-score"><span>{state.yourProfile.username} <b>{state.yourScore}</b></span><i>—</i><span><b>{state.opponentScore}</b> {state.opponentProfile.username} <SystemBadge visible={state.opponentProfile.is_system_player} /></span></div>
      <p>Your Record: {state.yourProfile.wins} Wins • {state.yourProfile.losses} Losses</p>
      {state.boonPointsEarned > 0 && <div className="boon-match-reward"><span>Boon Points Earned</span><strong>+{state.boonPointsEarned.toLocaleString()} BP</strong><small>Balance: {state.boonPointBalance.toLocaleString()} BP</small></div>}
      <Link className="button button-primary" to="/">Return to Lobby</Link>
    </section>
  }

  return <section className="battle-board">
    <header className="battle-score">
      <div className="battle-score-player"><span>{state.yourProfile.username}</span><strong>{state.yourScore}</strong></div>
      <div className="battle-score-round"><b>Round {state.roundNumber}</b><small>First to 3</small><span className="round-progress" aria-label={`${state.yourScore} of 3 rounds won`}>{[0, 1, 2].map((step) => <i key={step} className={step < state.yourScore ? 'filled' : undefined} />)}</span></div>
      <div className="battle-score-opponent"><strong>{state.opponentScore}</strong><span>{state.opponentProfile.username} <SystemBadge visible={state.opponentProfile.is_system_player} /></span></div>
    </header>
    {message && <p className="online-draft-message" role="status">{message}</p>}
    {state.yourBoonResolution?.status === 'no_eligible_target' && state.yourBoonResolution.boonKey && <div className="battle-boon-notice" role="status"><b>{state.yourBoonResolution.boonKey.replaceAll('_', ' ')}</b><span>No eligible target. The match continues normally.</span></div>}
    {state.yourBoonResolution?.status === 'condition_not_met' && state.yourBoonResolution.boonKey && <div className="battle-boon-notice" role="status"><b>{state.yourBoonResolution.boonKey.replaceAll('_', ' ')}</b><span>Condition not met. The match continues normally.</span></div>}
    {state.yourBoonResolution?.status === 'configuration_error' && state.yourBoonResolution.boonKey && <div className="battle-boon-notice" role="status"><b>{state.yourBoonResolution.boonKey.replaceAll('_', ' ')}</b><span>Boon could not activate. The match continues normally.</span></div>}
    {state.yourSupport && <div className="battle-support-banner"><strong>{state.yourSupport.decision === 'sacrifice' ? 'Sacrificial OC Activated' : 'Sacrificial OC Inactive'}</strong><span>{state.yourSupport.name} · {state.yourSupport.verseName}{state.yourSupport.decision === 'sacrifice' ? ` · ${state.yourSupport.recipientCount ?? 0} fighters empowered` : ''}</span></div>}
    {state.opponentSupport && <div className="battle-support-banner opponent"><strong>Sacrificial OC Revealed</strong><span>{state.opponentSupport.name} · {state.opponentSupport.verseName} · {state.opponentSupport.recipientCount ?? 0} fighters empowered</span></div>}
    {revealed ? <div className="battle-reveal">
      <div className="battle-result-fighters">
        <ResolvedCard fighter={revealed.yourFighter} character={yourRevealedCharacter} oc={revealed.yourFighter.type === 'oc' ? state.yourOC : null} imageUrl={yourImage} side="player" winner={roundWinner === 'player'} />
        <div className={`versus-result ${roundWinner}`}><span>VS</span><i aria-hidden="true">{roundWinner === 'draw' ? '—' : '♜'}</i><strong>{roundWinner === 'player' ? 'You Win' : roundWinner === 'opponent' ? 'You Lose' : 'Draw'}</strong></div>
        <ResolvedCard fighter={revealed.opponentFighter} character={opponentRevealedCharacter} oc={revealed.opponentFighter.type === 'oc' ? state.opponentOC : null} imageUrl={opponentImage} side="opponent" winner={roundWinner === 'opponent'} />
      </div>
      <button className="button button-primary result-continue" disabled={pendingAction !== null} onClick={() => { sounds.playNextRound(); if (finalRound) setShowFinalResult(true); else void onAdvance() }}>{pendingAction === 'advance' ? 'Advancing...' : finalRound ? 'View Match Result' : 'Next Round'}<span aria-hidden="true">›</span></button>
      <p className="result-helper"><i aria-hidden="true">i</i>{finalRound ? 'See the final score and match outcome.' : 'Continue when you’re ready.'}</p>
    </div> : <>
      <div className="opponent-roster"><h2>Opponent Team</h2><div>{state.opponentTeam.map((item) => <span key={item.id} className={item.used ? 'used' : undefined}>{item.character.name}</span>)}</div></div>
      <h2 className="fighter-heading">{yourSelection ? 'Fighter Locked In' : 'Choose Your Fighter'}</h2>
      <div className="battle-options"><div className="battle-hand" ref={battleHandRef}>{state.yourTeam.map((item) => <div key={item.id} data-fighter-id={item.id} className={`battle-hand-card${item.sacrificed ? ' battle-card-sacrificed' : ''}${item.empowered ? ' battle-card-empowered' : ''}${hasBoonEffect(item) ? ' battle-card-boon-enhanced' : ''}`}><GameCard character={item.character} compact showPower used={item.used || item.sacrificed} selected={(yourSelection?.id ?? selection?.id) === item.id} onHover={sounds.playCardHover} onClick={yourSelection || item.sacrificed || item.used ? undefined : () => selectFighter('canon', item.id)} />{item.sacrificed && <strong>ABSORBED</strong>}{item.empowered && <span><b>EMPOWERED</b><small>+{item.powerBoost?.toLocaleString()} Power</small></span>}{hasBoonEffect(item) && <span className="battle-card-boon" title={`Base ${item.baseOverall ?? item.character.overall} OVR · Boon ${signedValue(item.boonOverallBonus ?? 0)} OVR · Boon ${signedValue(item.boonPowerBonus ?? 0)} Power`}><b>BOON</b><small>{boonBonusText(item)}</small></span>}</div>)}</div>
      <div className="battle-hand-pagination" aria-label="Fighter selection">{state.yourTeam.map((item) => <button key={item.id} type="button" aria-label={`Select ${item.character.name}`} aria-current={(yourSelection?.id ?? selection?.id) === item.id ? 'true' : undefined} disabled={Boolean(yourSelection) || item.sacrificed || item.used} onClick={() => selectFighter('canon', item.id)} />)}</div>
      {state.yourOC && <button type="button" className={`oc-reserve-card ${state.yourOC.used ? 'used' : ''} ${selection?.type === 'oc' ? 'selected' : ''}`} disabled={Boolean(yourSelection) || state.yourOC.used} onMouseEnter={sounds.playCardHover} onClick={() => selectFighter('oc', state.yourOC!.id)}><small>OC Reserve</small><i>✦</i><strong>{state.yourOC.name}</strong><span className="oc-reserve-verse">{state.yourOC.verseName}</span><b>{state.yourOC.overall} OVR</b><span className="oc-reserve-power">{state.yourOC.powerScore.toLocaleString()} Power</span>{state.yourOC.boost > 0 && <em>Boosted +{state.yourOC.boost} OVR</em>}{hasBoonEffect(state.yourOC) && <span className="oc-boon-effect" title={`Base ${state.yourOC.baseOverall ?? state.yourOC.overall} OVR · Prep +${state.yourOC.preparationOverallBonus ?? 0} · Boon ${signedValue(state.yourOC.boonOverallBonus ?? 0)} OVR · Boon ${signedValue(state.yourOC.boonPowerBonus ?? 0)} Power`}>Boon · {boonBonusText(state.yourOC)}</span>}{selection?.type === 'oc' && <u>✓</u>}{state.yourOC.used && <u>Used</u>}</button>}</div>
      {yourSelection ? <p className="battle-lock-status">{state.opponentLocked ? 'Opponent locked in. Resolving round...' : 'Waiting for opponent...'}</p>
        : <><button className="button button-primary lock-button" disabled={!selection || pendingAction !== null} onClick={() => selection && void onLock(selection.type, selection.id)}><span className="lock-button-icon" aria-hidden="true">▣</span>{pendingAction === 'lock' ? 'Locking...' : 'Lock In'}</button><p className="battle-secret-note">▣ Your selection is secret until revealed</p></>}
      {!yourSelection && state.opponentLocked && <p className="battle-lock-status">Opponent has locked in.</p>}
    </>}
  </section>
}
