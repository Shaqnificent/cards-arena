import { supabase } from '../../../lib/supabase'
import type { Suggestion, SuggestionInput, SuggestionStatus } from '../types'

export async function getSuggestions(): Promise<Suggestion[]> {
  const { data, error } = await supabase.rpc('get_suggestions')
  if (error) throw error
  return (data ?? []) as Suggestion[]
}

export async function createSuggestion(authorId: string, input: SuggestionInput): Promise<void> {
  const { error } = await supabase.from('suggestions').insert({ author_id: authorId, ...input })
  if (error) throw error
}

export async function setSuggestionVote(suggestionId: string, playerId: string, voted: boolean): Promise<void> {
  const query = voted
    ? supabase.from('suggestion_votes').delete().eq('suggestion_id', suggestionId).eq('player_id', playerId)
    : supabase.from('suggestion_votes').insert({ suggestion_id: suggestionId, player_id: playerId })
  const { error } = await query
  if (error) throw error
}

export async function updateSuggestionStatus(suggestionId: string, status: SuggestionStatus): Promise<void> {
  const { error } = await supabase.rpc('set_suggestion_status', { p_suggestion_id: suggestionId, p_status: status })
  if (error) throw error
}
