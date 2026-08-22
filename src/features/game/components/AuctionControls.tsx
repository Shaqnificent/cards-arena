import type { DraftState, GamePlayer } from '../types'
import { isValidBid } from '../utils/gameRules'

interface AuctionControlsProps {
  draft: DraftState
  player: GamePlayer
  onBidStart: () => void
  onPass: () => void
  onBidChange: (bid: number) => void
  onPlaceBid: () => void
  onFold: () => void
  onContinue: () => void
}

export function AuctionControls({ draft, player, onBidStart, onPass, onBidChange, onPlaceBid, onFold, onContinue }: AuctionControlsProps) {
  if (draft.roundState === 'resolved') {
    return <div className="auction-feedback"><p>{draft.feedback}</p><button className="button button-primary" onClick={onContinue}>Next Character</button></div>
  }

  if (draft.aiThinking || draft.turn === 'opponent') {
    return <div className="ai-thinking" aria-live="polite"><span className="thinking-dot" />Opponent is thinking...</div>
  }

  if (draft.roundState === 'decision') {
    return (
      <div className="auction-actions">
        <button className="button button-primary" onClick={onBidStart}>Bid</button>
        <button className="button button-secondary" onClick={onPass}>Pass</button>
      </div>
    )
  }

  const valid = isValidBid(draft.proposedBid, draft.currentBid, player.balance)
  const canFold = draft.currentBid !== null && draft.leader === 'opponent'
  return (
    <div className="bid-controls">
      <p>Choose your next bid</p>
      <div className="bid-stepper">
        <button onClick={() => onBidChange(Math.max(0, draft.proposedBid - 1))} aria-label="Decrease bid">−</button>
        <strong>${draft.proposedBid}</strong>
        <button onClick={() => onBidChange(Math.min(player.balance, draft.proposedBid + 1))} aria-label="Increase bid">+</button>
      </div>
      <button className="button button-primary" disabled={!valid} onClick={onPlaceBid}>Place Bid</button>
      <button className="button button-secondary" disabled={!canFold} onClick={onFold}>Fold</button>
      {!valid && <small>Bid must exceed the current bid and stay within your ${player.balance} balance.</small>}
    </div>
  )
}
