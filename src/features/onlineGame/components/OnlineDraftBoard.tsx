import { useEffect, useRef } from 'react'
import { CharacterCard } from '../../../components/CharacterCard'
import type { OnlineDraftAction, OnlineDraftState } from '../types'
import { OnlineAuctionControls } from './OnlineAuctionControls'
import { OnlineTeamPanel } from './OnlineTeamPanel'
import { useGameSounds } from '../../audio/useGameSounds'

interface OnlineDraftBoardProps {
  state: OnlineDraftState
  currentUserId: string
  pendingAction: OnlineDraftAction
  message: string | null
  onBid: (amount: number) => Promise<void>
  onPass: () => Promise<void>
  onFold: () => Promise<void>
}

export function OnlineDraftBoard({ state, currentUserId, pendingAction, message, onBid, onPass, onFold }: OnlineDraftBoardProps) {
  const sounds = useGameSounds()
  const revealedPosition = useRef<number | null>(null)
  const { match } = state
  const isPlayerOne = currentUserId === match.player_one_id
  const yourProfile = isPlayerOne ? match.player_one : match.player_two
  const opponentProfile = isPlayerOne ? match.player_two : match.player_one
  const you = state.players.find((player) => player.player_id === currentUserId)
  const opponent = state.players.find((player) => player.player_id !== currentUserId)
  const yourTeam = state.revealedCharacters.filter((card) => card.owner_player_id === currentUserId)
  const opponentTeam = state.revealedCharacters.filter((card) => card.owner_player_id === opponent?.player_id)

  useEffect(() => {
    if (!state.currentCharacter || revealedPosition.current === match.current_draft_position) return
    revealedPosition.current = match.current_draft_position
    sounds.playRoundReveal()
  }, [match.current_draft_position, sounds, state.currentCharacter])

  if (!you || !opponent) return <div className="catalogue-state error-message">Online player state is unavailable.</div>

  if (match.status === 'battle' || match.draft_state === 'complete') {
    return (
      <section className="online-draft-complete">
        <p className="eyebrow">Online Draft Complete</p><h1>Teams Locked</h1>
        <div className="completed-team-grid">
          <OnlineTeamPanel label="Your Team" profile={yourProfile} player={you} team={yourTeam} />
          <OnlineTeamPanel label="Opponent Team" profile={opponentProfile} player={opponent} team={opponentTeam} />
        </div>
        <p>Battle synchronization is coming next.</p>
      </section>
    )
  }

  if (!state.currentCharacter) return <div className="ai-thinking"><span className="thinking-dot" />Preparing current draft card...</div>

  return (
    <section className="draft-board online-draft-board">
      <header className="game-phase-header">
        <div><span>Online Draft</span><strong>{match.current_draft_position} / 10</strong></div>
        <p>Priority: <b>{match.priority_player_id === currentUserId ? 'You' : opponentProfile.username}</b></p>
        <div><span>Current Bid</span><strong>{match.current_bid === null ? '—' : `$${match.current_bid}`}</strong></div>
      </header>
      {message && <p className="online-draft-message" role="status">{message}</p>}
      <div className="draft-layout">
        <div className="draft-team-slot draft-team-slot-player">
          <OnlineTeamPanel label="Your Team" profile={yourProfile} player={you} team={yourTeam} helperText="Build your team wisely." />
        </div>
        <div className="auction-character-card">
          <CharacterCard character={state.currentCharacter.character} />
        </div>
        <div className="draft-team-slot draft-team-slot-opponent">
          <OnlineTeamPanel label="Opponent Team" profile={opponentProfile} player={opponent} team={opponentTeam} helperText="Opponent is building their team..." />
        </div>
        <div className="auction-controls-slot">
          <OnlineAuctionControls
            match={match} you={you} userId={currentUserId} pendingAction={pendingAction}
            onBid={onBid} onPass={onPass} onFold={onFold}
          />
        </div>
      </div>
    </section>
  )
}
