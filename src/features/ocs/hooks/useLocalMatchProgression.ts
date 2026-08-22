import { useEffect, useRef, useState } from 'react'
import type { LocalGameState } from '../../game/types'
import { completeLocalProgressionMatch, startLocalProgressionMatch } from '../services/progression'
import type { LocalProgressionResult } from '../types'

export function useLocalMatchProgression(state: LocalGameState) {
  const [matchId, setMatchId] = useState<string | null>(null)
  const [result, setResult] = useState<LocalProgressionResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const startAttempted = useRef(false)
  const completionAttempted = useRef(false)

  useEffect(() => {
    if (state.phase !== 'draft' || matchId || startAttempted.current) return
    startAttempted.current = true
    void startLocalProgressionMatch()
      .then((id) => { setMatchId(id); setError(null) })
      .catch((startError) => { console.error('Local progression session failed', startError); setError('This local match is not eligible for OC progression.') })
  }, [matchId, state.phase])

  useEffect(() => {
    if (state.phase !== 'result' || !matchId || result || completionAttempted.current) return
    completionAttempted.current = true
    void completeLocalProgressionMatch(matchId, state.battle.playerScore, state.battle.opponentScore, state.battle.round)
      .then((completion) => { setResult(completion); setError(null) })
      .catch((completionError) => { console.error('Local progression completion failed', completionError); setError('Unable to record OC progression for this match.') })
  }, [matchId, result, state.battle.opponentScore, state.battle.playerScore, state.battle.round, state.phase])

  const reset = () => { startAttempted.current = false; completionAttempted.current = false; setMatchId(null); setResult(null); setError(null) }
  const pending = !error && (state.phase === 'draft' ? !matchId : state.phase === 'result' ? !result : false)
  return { result, error, pending, reset }
}
