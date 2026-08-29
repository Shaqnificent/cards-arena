import type { Character } from '../../../types/character'
import { CharacterCard } from '../../../components/CharacterCard'
import type { LocalGameState } from '../types'
import { AuctionControls } from './AuctionControls'
import { TeamPanel } from './TeamPanel'

interface DraftBoardProps {
  state: LocalGameState
  currentCharacter: Character
  actions: {
    playerPass: () => void; startPlayerBid: () => void; setProposedBid: (bid: number) => void
    placePlayerBid: () => void; playerFold: () => void; advanceDraft: () => void
  }
}

export function DraftBoard({ state, currentCharacter, actions }: DraftBoardProps) {
  return (
    <section className="draft-board">
      <header className="game-phase-header">
        <div><span>Draft Round</span><strong>{Math.min(state.currentIndex + 1, 10)} / 10</strong></div>
        <p>Priority: <b>{state.draft.priority === 'player' ? 'You' : 'Opponent'}</b></p>
        <div><span>Current Bid</span><strong>{state.draft.currentBid === null ? '—' : `$${state.draft.currentBid}`}</strong></div>
      </header>
      <div className="draft-layout">
        <div className="draft-team-slot draft-team-slot-player">
          <TeamPanel player={state.player} label="Your Team" helperText="Build your team wisely." />
        </div>
        <div className="auction-character-card">
          <CharacterCard character={currentCharacter} />
        </div>
        <div className="draft-team-slot draft-team-slot-opponent">
          <TeamPanel player={state.opponent} label="Opponent Team" helperText="Opponent is building their team..." />
        </div>
        <div className="auction-controls-slot">
          <AuctionControls
            draft={state.draft} player={state.player}
            onBidStart={actions.startPlayerBid} onPass={actions.playerPass}
            onBidChange={actions.setProposedBid} onPlaceBid={actions.placePlayerBid}
            onFold={actions.playerFold} onContinue={actions.advanceDraft}
          />
        </div>
      </div>
    </section>
  )
}
