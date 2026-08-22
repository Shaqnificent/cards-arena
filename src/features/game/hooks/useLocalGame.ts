import { useCallback, useEffect, useState } from 'react'
import type { Character } from '../../../types/character'
import type { LocalGameState, PlayerId } from '../types'
import { aiMaximumBid, aiWantsToBid, chooseOpponentCard } from '../utils/opponentAI'
import {
  awardCharacter,
  DRAFT_POOL_SIZE,
  getBattleWinner,
  getPriorityPlayer,
  isMatchWon,
  isValidBid,
  shuffleCharacters,
  STARTING_BALANCE,
  TEAM_SIZE,
} from '../utils/gameRules'

function createGame(characters: Character[], playerName: string): LocalGameState {
  if (characters.length < DRAFT_POOL_SIZE) {
    return {
      ...createEmptyState(playerName),
      error: `At least ${DRAFT_POOL_SIZE} active characters are required to start a match.`,
    }
  }

  const priority = getPriorityPlayer(STARTING_BALANCE, STARTING_BALANCE, 'player')
  return {
    ...createEmptyState(playerName),
    phase: 'draft',
    pool: shuffleCharacters(characters).slice(0, DRAFT_POOL_SIZE),
    draft: {
      ...createEmptyState(playerName).draft,
      priority: priority.priority,
      turn: priority.priority,
      nextTiePriority: priority.nextTiePriority,
    },
  }
}

function createEmptyState(playerName: string): LocalGameState {
  return {
    phase: 'loading', pool: [], currentIndex: 0,
    player: { id: 'player', name: playerName, balance: STARTING_BALANCE, team: [] },
    opponent: { id: 'opponent', name: 'Opponent', balance: STARTING_BALANCE, team: [] },
    draft: {
      roundState: 'decision', priority: 'player', nextTiePriority: 'opponent', turn: 'player',
      currentBid: null, leader: null, proposedBid: 0, feedback: null, aiThinking: false,
    },
    battle: {
      round: 1, playerScore: 0, opponentScore: 0, selectedPlayerId: null,
      playerUsedIds: [], opponentUsedIds: [], reveal: null,
    },
    winner: null, error: null,
  }
}

export function useLocalGame(characters: Character[], playerName: string) {
  const [state, setState] = useState<LocalGameState>(() => createGame(characters, playerName))

  const resolveCard = useCallback((winnerId: PlayerId, cost: number, feedback: string) => {
    setState((current) => {
      if (current.phase !== 'draft' || current.draft.roundState === 'resolved') return current
      const character = current.pool[current.currentIndex]
      if (!character) return { ...current, error: 'The draft pool ended unexpectedly.' }
      try {
        return {
          ...current,
          player: winnerId === 'player' ? awardCharacter(current.player, character, cost) : current.player,
          opponent: winnerId === 'opponent' ? awardCharacter(current.opponent, character, cost) : current.opponent,
          draft: { ...current.draft, roundState: 'resolved', feedback, aiThinking: false },
        }
      } catch (error) {
        return { ...current, error: error instanceof Error ? error.message : 'Unable to resolve auction.' }
      }
    })
  }, [])

  const advanceDraft = useCallback(() => {
    setState((current) => {
      if (current.phase !== 'draft' || current.draft.roundState !== 'resolved') return current
      let player = current.player
      let opponent = current.opponent
      let nextIndex = current.currentIndex + 1

      try {
        if (player.team.length === TEAM_SIZE || opponent.team.length === TEAM_SIZE) {
          const recipient: PlayerId = player.team.length === TEAM_SIZE ? 'opponent' : 'player'
          while (nextIndex < current.pool.length) {
            const character = current.pool[nextIndex]
            if (recipient === 'player') player = awardCharacter(player, character, 0)
            else opponent = awardCharacter(opponent, character, 0)
            nextIndex += 1
          }
        }
      } catch (error) {
        return { ...current, error: error instanceof Error ? error.message : 'Invalid roster state.' }
      }

      if (player.team.length === TEAM_SIZE && opponent.team.length === TEAM_SIZE) {
        return { ...current, phase: 'battle', player, opponent, currentIndex: nextIndex }
      }
      if (nextIndex >= current.pool.length) return { ...current, error: 'Draft ended before both rosters were complete.' }

      const priority = getPriorityPlayer(player.balance, opponent.balance, current.draft.nextTiePriority)
      return {
        ...current, player, opponent, currentIndex: nextIndex,
        draft: {
          roundState: 'decision', priority: priority.priority, nextTiePriority: priority.nextTiePriority,
          turn: priority.priority, currentBid: null, leader: null, proposedBid: 0,
          feedback: null, aiThinking: priority.priority === 'opponent',
        },
      }
    })
  }, [])

  const playerPass = useCallback(() => {
    if (state.draft.priority !== 'player' || state.draft.roundState !== 'decision') return
    resolveCard('opponent', 0, `You passed. Opponent received ${state.pool[state.currentIndex]?.name} for $0.`)
  }, [resolveCard, state])

  const startPlayerBid = useCallback(() => {
    setState((current) => current.phase === 'draft' && current.draft.roundState === 'decision' && current.draft.priority === 'player'
      ? { ...current, draft: { ...current.draft, roundState: 'bidding', turn: 'player', proposedBid: Math.min(1, current.player.balance) } }
      : current)
  }, [])

  const setProposedBid = useCallback((bid: number) => {
    setState((current) => ({ ...current, draft: { ...current.draft, proposedBid: bid } }))
  }, [])

  const placePlayerBid = useCallback(() => {
    setState((current) => {
      if (current.phase !== 'draft' || current.draft.roundState !== 'bidding' || current.draft.turn !== 'player') return current
      if (!isValidBid(current.draft.proposedBid, current.draft.currentBid, current.player.balance)) return current
      return {
        ...current,
        draft: {
          ...current.draft, currentBid: current.draft.proposedBid, leader: 'player', turn: 'opponent', aiThinking: true,
        },
      }
    })
  }, [])

  const playerFold = useCallback(() => {
    if (state.draft.roundState !== 'bidding' || state.draft.turn !== 'player' || state.draft.leader !== 'opponent') return
    const cost = state.draft.currentBid ?? 0
    resolveCard('opponent', cost, `You folded. Opponent won ${state.pool[state.currentIndex]?.name} for $${cost}.`)
  }, [resolveCard, state])

  useEffect(() => {
    if (state.phase !== 'draft' || state.draft.turn !== 'opponent' || state.draft.roundState === 'resolved') return
    const timer = window.setTimeout(() => {
      const character = state.pool[state.currentIndex]
      if (!character) return
      const slotsRemaining = TEAM_SIZE - state.opponent.team.length

      if (state.draft.roundState === 'decision') {
        if (!aiWantsToBid(character, state.opponent.balance, slotsRemaining)) {
          resolveCard('player', 0, `Opponent passed. You received ${character.name} for $0.`)
          return
        }
        const bid = Math.min(state.opponent.balance, Math.max(0, Math.min(3, aiMaximumBid(character, state.opponent.balance, slotsRemaining))))
        setState((current) => ({
          ...current,
          draft: { ...current.draft, roundState: 'bidding', currentBid: bid, leader: 'opponent', turn: 'player', proposedBid: Math.min(current.player.balance, bid + 1), aiThinking: false },
        }))
        return
      }

      const currentBid = state.draft.currentBid ?? 0
      const maximumBid = aiMaximumBid(character, state.opponent.balance, slotsRemaining)
      if (currentBid < maximumBid && currentBid < state.opponent.balance) {
        const raise = Math.min(maximumBid, state.opponent.balance, currentBid + 1 + Math.floor(Math.random() * 3))
        setState((current) => ({
          ...current,
          draft: { ...current.draft, currentBid: raise, leader: 'opponent', turn: 'player', proposedBid: Math.min(current.player.balance, raise + 1), aiThinking: false },
        }))
      } else {
        resolveCard('player', currentBid, `Opponent folded. You won ${character.name} for $${currentBid}.`)
      }
    }, 650)
    return () => window.clearTimeout(timer)
  }, [resolveCard, state])

  const selectBattleCard = useCallback((id: string) => {
    setState((current) => {
      if (current.phase !== 'battle' || current.battle.reveal || current.battle.playerUsedIds.includes(id)) return current
      return { ...current, battle: { ...current.battle, selectedPlayerId: id } }
    })
  }, [])

  const lockBattleCard = useCallback(() => {
    setState((current) => {
      if (current.phase !== 'battle' || current.battle.reveal || !current.battle.selectedPlayerId) return current
      const playerCard = current.player.team.find((card) => card.id === current.battle.selectedPlayerId)
      if (!playerCard || current.battle.playerUsedIds.includes(playerCard.id)) return current
      try {
        const opponentCard = chooseOpponentCard(current.opponent.team, current.battle.opponentUsedIds)
        const winner = getBattleWinner(playerCard, opponentCard)
        return {
          ...current,
          battle: {
            ...current.battle,
            playerScore: current.battle.playerScore + (winner === 'player' ? 1 : 0),
            opponentScore: current.battle.opponentScore + (winner === 'opponent' ? 1 : 0),
            playerUsedIds: [...current.battle.playerUsedIds, playerCard.id],
            opponentUsedIds: [...current.battle.opponentUsedIds, opponentCard.id],
            reveal: { playerCard, opponentCard, winner },
          },
        }
      } catch (error) {
        return { ...current, error: error instanceof Error ? error.message : 'Unable to resolve battle round.' }
      }
    })
  }, [])

  const continueBattle = useCallback(() => {
    setState((current) => {
      if (current.phase !== 'battle' || !current.battle.reveal) return current
      const complete = isMatchWon(current.battle.playerScore, current.battle.opponentScore) || current.battle.round >= TEAM_SIZE
      if (complete) {
        const winner = current.battle.playerScore > current.battle.opponentScore ? 'player'
          : current.battle.opponentScore > current.battle.playerScore ? 'opponent' : 'draw'
        return { ...current, phase: 'result', winner }
      }
      return {
        ...current,
        battle: { ...current.battle, round: current.battle.round + 1, selectedPlayerId: null, reveal: null },
      }
    })
  }, [])

  const restart = useCallback(() => setState(createGame(characters, playerName)), [characters, playerName])

  return {
    state, currentCharacter: state.pool[state.currentIndex] ?? null,
    actions: { playerPass, startPlayerBid, setProposedBid, placePlayerBid, playerFold, advanceDraft, selectBattleCard, lockBattleCard, continueBattle, restart },
  }
}
