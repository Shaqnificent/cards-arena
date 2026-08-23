import { useCallback, useEffect, useRef, useState } from 'react'
import type { AdministratorToastMessage } from '../../../components/AdministratorToast'
import type { AdministratorQuoteContext } from '../../../data/administratorQuotes'
import { getAdministratorResultQuoteContext, getRandomAdministratorQuote } from '../../../lib/administratorQuoteUtils'
import { supabase } from '../../../lib/supabase'

interface MatchInteractionSnapshot {
  id: string
  player_one_id: string
  player_two_id: string
  player_one_score: number
  player_two_score: number
  winner_id: string | null
  status: string
}

interface AdministratorIdentity {
  id: string
  username: string
  avatar_url: string | null
  is_system_player: boolean
}

const interactionFallback = new Set<string>()
const scheduledInteractions = new Set<string>()

function interactionWasShown(key: string): boolean {
  if (interactionFallback.has(key)) return true
  try { return window.sessionStorage.getItem(key) !== null }
  catch { return false }
}

function markInteractionShown(key: string, quote: string): void {
  interactionFallback.add(key)
  try { window.sessionStorage.setItem(key, quote) }
  catch { /* The in-memory key still prevents StrictMode duplicates. */ }
}

async function loadAdministratorMatch(matchId: string, currentUserId: string): Promise<{
  match: MatchInteractionSnapshot
  administrator: AdministratorIdentity
} | null> {
  const { data: match, error: matchError } = await supabase
    .from('matches')
    .select('id, player_one_id, player_two_id, player_one_score, player_two_score, winner_id, status')
    .eq('id', matchId)
    .maybeSingle<MatchInteractionSnapshot>()
  if (matchError || !match || ![match.player_one_id, match.player_two_id].includes(currentUserId)) return null

  const opponentId = match.player_one_id === currentUserId ? match.player_two_id : match.player_one_id
  const { data: opponent, error: profileError } = await supabase
    .from('profiles')
    .select('id, username, avatar_url, is_system_player')
    .eq('id', opponentId)
    .maybeSingle<AdministratorIdentity>()
  if (profileError || !opponent?.is_system_player) return null
  return { match, administrator: opponent }
}

export function useAdministratorInteractions(matchId: string, currentUserId: string) {
  const [toast, setToast] = useState<AdministratorToastMessage | null>(null)
  const startTimer = useRef<number | null>(null)
  const resultTimer = useRef<number | null>(null)
  const dismissTimer = useRef<number | null>(null)
  const resultRequestPending = useRef(false)

  const showInteraction = useCallback((context: AdministratorQuoteContext, administrator: AdministratorIdentity, delayMs: number, durationMs: number) => {
    const eventName = context === 'match_start' ? 'start' : 'result'
    const key = `admin-${eventName}:${matchId}`
    if (interactionWasShown(key) || scheduledInteractions.has(key)) return
    scheduledInteractions.add(key)

    const timer = window.setTimeout(() => {
      scheduledInteractions.delete(key)
      if (interactionWasShown(key)) return
      const quote = getRandomAdministratorQuote(context)
      if (!quote) return
      markInteractionShown(key, quote)
      setToast({ context, quote, username: administrator.username, avatarUrl: administrator.avatar_url, durationMs })
      if (dismissTimer.current !== null) window.clearTimeout(dismissTimer.current)
      dismissTimer.current = window.setTimeout(() => setToast(null), durationMs)
    }, delayMs)

    return timer
  }, [matchId])

  useEffect(() => {
    let active = true
    void loadAdministratorMatch(matchId, currentUserId).then((result) => {
      if (!active || !result || result.match.status === 'completed' || result.match.status === 'cancelled') return
      startTimer.current = showInteraction('match_start', result.administrator, 650, 4600) ?? null
    })
    return () => {
      active = false
      if (startTimer.current !== null) {
        window.clearTimeout(startTimer.current)
        scheduledInteractions.delete(`admin-start:${matchId}`)
      }
      if (resultTimer.current !== null) {
        window.clearTimeout(resultTimer.current)
        scheduledInteractions.delete(`admin-result:${matchId}`)
      }
      if (dismissTimer.current !== null) window.clearTimeout(dismissTimer.current)
    }
  }, [currentUserId, matchId, showInteraction])

  const notifyResultVisible = useCallback(() => {
    if (resultRequestPending.current || interactionWasShown(`admin-result:${matchId}`)) return
    resultRequestPending.current = true
    void loadAdministratorMatch(matchId, currentUserId)
      .then((result) => {
        if (!result || result.match.status !== 'completed') return
        const context = getAdministratorResultQuoteContext({
          administratorId: result.administrator.id,
          humanPlayerId: currentUserId,
          playerOneId: result.match.player_one_id,
          playerTwoId: result.match.player_two_id,
          playerOneScore: result.match.player_one_score,
          playerTwoScore: result.match.player_two_score,
          winnerId: result.match.winner_id,
        })
        if (context) resultTimer.current = showInteraction(context, result.administrator, 700, 5400) ?? null
      })
      .finally(() => { resultRequestPending.current = false })
  }, [currentUserId, matchId, showInteraction])

  return { toast, notifyResultVisible }
}
