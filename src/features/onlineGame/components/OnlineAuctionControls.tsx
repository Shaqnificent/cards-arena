import { useState } from 'react'
import type { OnlineDraftAction, OnlineMatchPlayer, OnlineMatchRecord } from '../types'

interface OnlineAuctionControlsProps {
  match: OnlineMatchRecord
  you: OnlineMatchPlayer
  userId: string
  pendingAction: OnlineDraftAction
  onBid: (amount: number) => Promise<void>
  onPass: () => Promise<void>
  onFold: () => Promise<void>
}

export function OnlineAuctionControls({ match, you, userId, pendingAction, onBid, onPass, onFold }: OnlineAuctionControlsProps) {
  const [choosingOpeningBid, setChoosingOpeningBid] = useState(false)
  const minimumBid = match.current_bid === null ? 0 : match.current_bid + 1
  const [proposedBid, setProposedBid] = useState(minimumBid)
  const effectiveBid = Math.max(proposedBid, minimumBid)
  const isPriority = match.priority_player_id === userId
  const isLeading = match.current_bidder_id === userId
  const canAffordRaise = effectiveBid <= you.balance

  if (pendingAction) return <div className="ai-thinking"><span className="thinking-dot" />Submitting {pendingAction}...</div>

  if (match.draft_state === 'decision' && !choosingOpeningBid) {
    return isPriority ? (
      <div className="auction-actions">
        <button className="button button-primary" onClick={() => setChoosingOpeningBid(true)}>Bid</button>
        <button className="button button-secondary" onClick={() => void onPass()}>Pass</button>
      </div>
    ) : <div className="ai-thinking"><span className="thinking-dot" />Waiting for opponent...</div>
  }

  if (match.draft_state === 'bidding' && isLeading) {
    return <div className="online-leading"><strong>Your bid: ${match.current_bid}</strong><p>Waiting for opponent...</p></div>
  }

  const canAct = choosingOpeningBid && isPriority || match.draft_state === 'bidding' && !isLeading
  if (!canAct) return <div className="ai-thinking"><span className="thinking-dot" />Waiting for opponent...</div>

  return (
    <div className="bid-controls">
      <p>{match.current_bid === null ? 'Choose an opening bid' : `Current bid: $${match.current_bid}`}</p>
      <div className="bid-stepper">
        <button onClick={() => setProposedBid(Math.max(minimumBid, effectiveBid - 1))} aria-label="Decrease bid">−</button>
        <strong>${effectiveBid}</strong>
        <button onClick={() => setProposedBid(Math.min(you.balance, effectiveBid + 1))} aria-label="Increase bid">+</button>
      </div>
      <button className="button button-primary" disabled={!canAffordRaise} onClick={() => void onBid(effectiveBid)}>Place Bid</button>
      {match.draft_state === 'bidding' && <button className="button button-secondary" onClick={() => void onFold()}>Fold</button>}
      {!canAffordRaise && <small>Your ${you.balance} balance cannot cover the next bid. You can fold.</small>}
    </div>
  )
}
