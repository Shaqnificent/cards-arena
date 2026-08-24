import { useEffect, useRef, useState } from 'react'
import paperIcon from '../../../assets/pre_draft/paper.svg'
import rockIcon from '../../../assets/pre_draft/rock.svg'
import scissorsIcon from '../../../assets/pre_draft/scissors.svg'
import { useGameSounds } from '../../audio/useGameSounds'
import type { InitiativeChoice, OnlineInitiativeState } from '../types'
import { MatchBoonCard } from './MatchBoonCard'

const choices: InitiativeChoice[] = ['rock', 'paper', 'scissors']
const choiceIcons: Record<InitiativeChoice, string> = {
  rock: rockIcon,
  paper: paperIcon,
  scissors: scissorsIcon,
}

const toastExpiryFallback = new Map<string, number>()

type InitiativeToastMessage = {
  key: string
  title: string
  detail: string
  kind: 'locked' | 'result'
}

interface Props {
  initiative: OnlineInitiativeState
  message: string | null
  onLock: (choice: InitiativeChoice) => Promise<void>
}

function titleCase(choice: InitiativeChoice) {
  return `${choice.charAt(0).toUpperCase()}${choice.slice(1)}`
}

function claimToastTime(key: string, durationMs: number) {
  const storageKey = `anime-arena:${key}`
  const now = Date.now()

  try {
    const storedExpiry = Number(window.sessionStorage.getItem(storageKey))
    if (Number.isFinite(storedExpiry) && storedExpiry > 0) return Math.max(0, storedExpiry - now)

    const expiry = now + durationMs
    window.sessionStorage.setItem(storageKey, String(expiry))
    return durationMs
  } catch {
    const storedExpiry = toastExpiryFallback.get(storageKey)
    if (storedExpiry) return Math.max(0, storedExpiry - now)

    toastExpiryFallback.set(storageKey, now + durationMs)
    return durationMs
  }
}

function ChoiceVisual({ choice, size = 'selection' }: { choice: InitiativeChoice; size?: 'selection' | 'result' }) {
  return <img className={`initiative-choice-icon size-${size}`} src={choiceIcons[choice]} alt="" aria-hidden="true" />
}

function InitiativeSelection({
  selected,
  locking,
  onSelect,
  onSubmit,
  onHover,
}: {
  selected: InitiativeChoice | null
  locking: boolean
  onSelect: (choice: InitiativeChoice) => void
  onSubmit: () => void
  onHover: () => void
}) {
  return <>
    <p className="initiative-section-label">Choose your move</p>
    <p className="initiative-helper">Your choice stays hidden until both players lock.</p>
    <div className="initiative-choices" role="group" aria-label="Choose rock, paper, or scissors">
      {choices.map((choice) => <button
        type="button"
        key={choice}
        className={selected === choice ? 'selected' : ''}
        aria-pressed={selected === choice}
        onMouseEnter={onHover}
        onClick={() => onSelect(choice)}
      >
        <ChoiceVisual choice={choice} />
        <span>{choice}</span>
      </button>)}
    </div>
    <button
      type="button"
      className="button button-primary initiative-lock"
      disabled={!selected || locking}
      onClick={onSubmit}
    >
      {locking ? 'Locking...' : 'Lock In'}
    </button>
  </>
}

function InitiativeLocked({ choice }: { choice: InitiativeChoice }) {
  return <>
    <p className="initiative-section-label">Move locked</p>
    <div className="initiative-locked">
      <ChoiceVisual choice={choice} size="result" />
      <strong>{choice}</strong>
    </div>
    <p className="initiative-locked-title">Waiting for the reveal...</p>
    <p className="initiative-helper">Your choice remains hidden until both players lock.</p>
  </>
}

function InitiativeResult({ initiative }: { initiative: OnlineInitiativeState }) {
  if (!initiative.yourChoice || !initiative.opponentChoice) return null

  const youWon = initiative.winnerPlayerId === initiative.yourPlayerId
  const yourEmphasis = initiative.isDraw ? 'draw' : youWon ? 'winner' : 'subdued'
  const opponentEmphasis = initiative.isDraw ? 'draw' : youWon ? 'subdued' : 'winner'
  const resultTitle = initiative.isDraw
    ? 'Draw'
    : youWon
      ? 'You won initiative'
      : 'Opponent won initiative'
  const resultDetail = initiative.isDraw
    ? `Both players chose ${titleCase(initiative.yourChoice)}`
    : youWon
      ? `${titleCase(initiative.yourChoice)} defeats ${titleCase(initiative.opponentChoice)}`
      : `${titleCase(initiative.opponentChoice)} defeats ${titleCase(initiative.yourChoice)}`

  return <div className="initiative-result" role="status" aria-label={`${resultTitle}. ${resultDetail}.`}>
    <p className="initiative-result-label">Round results</p>
    <div className="initiative-matchup">
      <div className={`initiative-result-move ${yourEmphasis}`}>
        <ChoiceVisual choice={initiative.yourChoice} size="result" />
        <strong>{initiative.yourChoice}</strong>
        <small>You</small>
      </div>
      <span className="initiative-versus" aria-hidden="true">VS</span>
      <div className={`initiative-result-move ${opponentEmphasis}`}>
        <ChoiceVisual choice={initiative.opponentChoice} size="result" />
        <strong>{initiative.opponentChoice}</strong>
        <small>Opponent</small>
      </div>
    </div>
    <h2>{resultTitle}</h2>
    <p className="initiative-result-detail">{resultDetail}</p>
    <small className="initiative-transition-note">
      {initiative.isDraw ? 'Preparing the next initiative round...' : 'Preparing OC selection...'}
    </small>
  </div>
}

function InitiativeRules() {
  return <aside className="initiative-rules" aria-label="Initiative rules">
    <span aria-hidden="true">i</span>
    <p>Rock beats Scissors <b>•</b> Scissors beats Paper <b>•</b> Paper beats Rock</p>
  </aside>
}

function InitiativeToast({ toast }: { toast: InitiativeToastMessage }) {
  return <aside
    key={toast.key}
    className={`initiative-toast kind-${toast.kind}`}
    role="status"
    aria-live="polite"
    aria-atomic="true"
  >
    <span className="initiative-toast-icon" aria-hidden="true">{toast.kind === 'locked' ? '▣' : '◆'}</span>
    <div>
      <strong>{toast.title}</strong>
      <p>{toast.detail}</p>
    </div>
  </aside>
}

export function InitiativeScreen({ initiative, message, onLock }: Props) {
  const [selected, setSelected] = useState<InitiativeChoice | null>(null)
  const [locking, setLocking] = useState(false)
  const [toast, setToast] = useState<InitiativeToastMessage | null>(null)
  const sounds = useGameSounds()
  const revealed = initiative.initiativeState === 'revealed'
  const lockSeen = useRef(Boolean(initiative.yourChoice))
  const revealSeen = useRef(false)
  const youWon = initiative.winnerPlayerId === initiative.yourPlayerId

  useEffect(() => {
    if (!lockSeen.current && initiative.yourChoice) sounds.playLockIn()
    lockSeen.current = Boolean(initiative.yourChoice)
  }, [initiative.yourChoice, sounds])

  useEffect(() => {
    if (!revealed || revealSeen.current) return
    revealSeen.current = true
    sounds.playRoundReveal()
    const resultTimer = window.setTimeout(() => {
      if (initiative.isDraw) sounds.playRoundDraw()
      else if (youWon) sounds.playRoundWin()
      else sounds.playRoundLose()
    }, 180)
    return () => window.clearTimeout(resultTimer)
  }, [initiative.isDraw, revealed, sounds, youWon])

  useEffect(() => {
    if (revealed || !initiative.opponentLocked) return

    const key = `initiative-opponent-locked:${initiative.matchId}:${initiative.initiativeRound}`
    const remainingMs = claimToastTime(key, 2700)
    if (remainingMs <= 0) return

    const nextToast: InitiativeToastMessage = {
      key,
      title: 'Opponent has locked in',
      detail: `Get ready for Round ${initiative.initiativeRound}`,
      kind: 'locked',
    }
    const showTimer = window.setTimeout(() => setToast(nextToast), 0)
    const dismissTimer = window.setTimeout(() => {
      setToast((current) => current?.key === key ? null : current)
    }, remainingMs)
    return () => {
      window.clearTimeout(showTimer)
      window.clearTimeout(dismissTimer)
    }
  }, [initiative.initiativeRound, initiative.matchId, initiative.opponentLocked, revealed])

  useEffect(() => {
    if (!revealed || !initiative.yourChoice || !initiative.opponentChoice) return

    const key = `initiative-result:${initiative.matchId}:${initiative.initiativeRound}`
    const remainingMs = claimToastTime(key, 2600)
    if (remainingMs <= 0) return

    const nextToast: InitiativeToastMessage = initiative.isDraw
      ? { key, title: 'Initiative draw', detail: 'Another round is required', kind: 'result' }
      : youWon
        ? { key, title: 'You won initiative', detail: 'Received first draft priority • Preparing OC selection', kind: 'result' }
        : { key, title: 'Opponent won initiative', detail: 'Opponent received first draft priority • Preparing OC selection', kind: 'result' }
    const showTimer = window.setTimeout(() => setToast(nextToast), 0)
    const dismissTimer = window.setTimeout(() => {
      setToast((current) => current?.key === key ? null : current)
    }, remainingMs)
    return () => {
      window.clearTimeout(showTimer)
      window.clearTimeout(dismissTimer)
    }
  }, [initiative.initiativeRound, initiative.isDraw, initiative.matchId, initiative.opponentChoice, initiative.yourChoice, revealed, youWon])

  const selectChoice = (choice: InitiativeChoice) => {
    if (selected === choice) return
    setSelected(choice)
    sounds.playCardSelect()
  }

  const lock = async () => {
    if (!selected || locking) return
    setLocking(true)
    try {
      await onLock(selected)
    } finally {
      setLocking(false)
    }
  }

  return <main className="initiative-page">
    <header className="initiative-phase-bar">
      <span>Pre-Draft</span><b aria-hidden="true">•</b><span>Round {initiative.initiativeRound}</span>
    </header>
    <div className="initiative-stage">
      <section className="initiative-boon-reveal" aria-label="Ranked match Boons">
        <MatchBoonCard label="Your Boon" boon={initiative.yourBoon} />
        <MatchBoonCard label="Opponent Boon" boon={initiative.opponentBoon} revealed={initiative.opponentBoonRevealed} />
      </section>
      <section className={`initiative-card ${revealed ? 'state-result' : 'state-choice'}`}>
        <h1>Initiative</h1>
        {message && <p className="online-draft-message" role="status">{message}</p>}
        {revealed
          ? <InitiativeResult initiative={initiative} />
          : initiative.yourChoice
            ? <InitiativeLocked choice={initiative.yourChoice} />
            : <InitiativeSelection
                selected={selected}
                locking={locking}
                onSelect={selectChoice}
                onSubmit={() => void lock()}
                onHover={sounds.playCardHover}
              />}
      </section>
      <InitiativeRules />
    </div>
    {toast && <InitiativeToast toast={toast} />}
  </main>
}
