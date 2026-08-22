import { useCallback, useEffect, useState } from 'react'
import { createSuggestion, getSuggestions, setSuggestionVote, updateSuggestionStatus } from '../services/suggestions'
import type { Suggestion, SuggestionInput, SuggestionStatus } from '../types'

export function useSuggestions(currentUserId: string) {
  const [suggestions, setSuggestions] = useState<Suggestion[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [pendingId, setPendingId] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    try { setSuggestions(await getSuggestions()); setError(null) }
    catch (loadError) { console.error('Suggestions load failed', loadError); setError('Unable to load suggestions.') }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { void Promise.resolve().then(refresh) }, [refresh])

  const submit = async (input: SuggestionInput) => {
    setMessage(null)
    await createSuggestion(currentUserId, input)
    await refresh()
    setMessage('Suggestion submitted.')
  }
  const toggleVote = async (suggestion: Suggestion) => {
    if (pendingId) return
    setPendingId(suggestion.id)
    try { await setSuggestionVote(suggestion.id, currentUserId, suggestion.current_user_voted); await refresh() }
    catch (voteError) { console.error('Suggestion vote failed', voteError); setMessage('Unable to update your vote.') }
    finally { setPendingId(null) }
  }
  const setStatus = async (suggestionId: string, status: SuggestionStatus) => {
    setPendingId(suggestionId)
    try { await updateSuggestionStatus(suggestionId, status); await refresh() }
    catch (statusError) { console.error('Suggestion status update failed', statusError); setMessage('Unable to update suggestion status.') }
    finally { setPendingId(null) }
  }
  return { suggestions, loading, error, message, pendingId, refresh, submit, toggleVote, setStatus }
}
