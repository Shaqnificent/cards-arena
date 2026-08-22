import { supabase } from '../../../lib/supabase'
import type { Profile } from '../../../types/profile'
import type { Character } from '../../../types/character'
import type { InitiativeChoice, MatchOcSelectionState, OnlineDraftState, OnlineInitiativeState, OnlineMatchCharacter, OnlineMatchPlayer, OnlineMatchRecord } from '../types'
import type { MatchStatus } from '../../matchmaking/types'
import { loadMatchOcPortraits } from './matchOcPortraits'

type MatchRow = Omit<OnlineMatchRecord, 'player_one' | 'player_two'> & {
  player_one: Profile | Profile[]
  player_two: Profile | Profile[]
}

type MatchCharacterRow = Omit<OnlineMatchCharacter, 'character'> & {
  character: Character | Character[]
}

async function withOcPortraits(matchId: string, state: MatchOcSelectionState): Promise<MatchOcSelectionState> {
  const portraits = await loadMatchOcPortraits(matchId)
  return { ...state,
    yourOptions: state.yourOptions.map((option) => ({ ...option, imageUrl: portraits.get(option.characterId) ?? null })),
    opponentOptions: state.opponentOptions.map((option) => ({ ...option, imageUrl: portraits.get(option.characterId) ?? null })),
  }
}

export async function initializeOnlineDraft(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('initialize_match_draft', { p_match_id: matchId })
  if (error) {
    console.error('initialize_match_draft failed', {
      matchId,
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    })
    throw error
  }
}

export async function initializeMatchInitiative(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('initialize_match_initiative', { p_match_id: matchId })
  if (error) throw error
}

export async function initializeMatchOcSelection(matchId: string): Promise<MatchOcSelectionState> {
  const { data, error } = await supabase.rpc('initialize_match_oc_selection', { p_match_id: matchId })
  if (error) throw error
  return withOcPortraits(matchId, data as MatchOcSelectionState)
}

export async function loadMatchOcSelection(matchId: string, currentUserId: string): Promise<MatchOcSelectionState> {
  const { data, error } = await supabase.rpc('get_match_oc_selection_state', { p_match_id: matchId })
  if (error) throw error
  const state = data as MatchOcSelectionState | null
  if (!state || state.yourPlayerId !== currentUserId) throw new Error('OC selection state unavailable')
  return withOcPortraits(matchId, state)
}

export async function submitMatchOcSelection(matchId: string, characterId: string): Promise<MatchOcSelectionState> {
  const { data, error } = await supabase.rpc('submit_match_oc_selection', { p_match_id: matchId, p_character_id: characterId })
  if (error) throw error
  return withOcPortraits(matchId, data as MatchOcSelectionState)
}

export async function validateMatchParticipant(matchId: string, currentUserId: string): Promise<MatchStatus> {
  const { data, error } = await supabase
    .from('matches')
    .select('id, player_one_id, player_two_id, status')
    .eq('id', matchId)
    .maybeSingle()
  if (error || !data) throw error ?? new Error('Match unavailable')
  if (![data.player_one_id, data.player_two_id].includes(currentUserId)) throw new Error('Match unavailable')
  return data.status as MatchStatus
}

export async function loadMatchInitiative(matchId: string, currentUserId: string): Promise<OnlineInitiativeState> {
  const { data, error } = await supabase.rpc('get_match_initiative_state', { p_match_id: matchId })
  if (error) throw error
  const state = data as OnlineInitiativeState | null
  if (!state || state.yourPlayerId !== currentUserId) throw new Error('Initiative state unavailable')
  return state
}

export async function submitInitiativeChoice(matchId: string, choice: InitiativeChoice): Promise<void> {
  const { error } = await supabase.rpc('submit_initiative_choice', { p_match_id: matchId, p_choice: choice })
  if (error) throw error
}

export async function advanceInitiativeRound(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('advance_initiative_round', { p_match_id: matchId })
  if (error) throw error
}

export async function loadOnlineDraft(matchId: string, currentUserId: string, attempt = 0): Promise<OnlineDraftState> {
  const [matchResult, playersResult, charactersResult] = await Promise.all([
    supabase.from('matches').select(`
      *,
      player_one:profiles!matches_player_one_id_fkey (*),
      player_two:profiles!matches_player_two_id_fkey (*)
    `).eq('id', matchId).maybeSingle(),
    supabase.from('match_players').select('*').eq('match_id', matchId).order('player_number'),
    supabase.from('match_characters').select(`
      id, match_id, character_id, draft_position, owner_player_id, purchase_price, assigned_at,
      character:characters!match_characters_character_id_fkey (
        id, name, slug, version, image_url, overall, power_score, active, verse_id,
        verses (id, name, slug)
      )
    `).eq('match_id', matchId).order('draft_position'),
  ])

  if (matchResult.error || !matchResult.data) throw matchResult.error ?? new Error('Match unavailable')
  if (playersResult.error) throw playersResult.error
  if (charactersResult.error) throw charactersResult.error

  const rawMatch = matchResult.data as unknown as MatchRow
  if (![rawMatch.player_one_id, rawMatch.player_two_id].includes(currentUserId)) throw new Error('Match unavailable')
  const playerOne = Array.isArray(rawMatch.player_one) ? rawMatch.player_one[0] : rawMatch.player_one
  const playerTwo = Array.isArray(rawMatch.player_two) ? rawMatch.player_two[0] : rawMatch.player_two
  if (!playerOne || !playerTwo) throw new Error('Match profiles unavailable')

  const revealedCharacters = ((charactersResult.data ?? []) as unknown as MatchCharacterRow[]).flatMap((row) => {
    const character = Array.isArray(row.character) ? row.character[0] : row.character
    return character ? [{ ...row, character }] : []
  })
  const match: OnlineMatchRecord = { ...rawMatch, player_one: playerOne, player_two: playerTwo }

  // The state spans normalized tables. Verify no action committed between the
  // parallel reads; retrying gives the UI one coherent authoritative version.
  const { data: versionRow, error: versionError } = await supabase
    .from('matches').select('action_version').eq('id', matchId).single()
  if (versionError) throw versionError
  if (versionRow.action_version !== match.action_version && attempt < 2) {
    return loadOnlineDraft(matchId, currentUserId, attempt + 1)
  }

  if (match.status === 'waiting' || match.status === 'initiative' || match.status === 'oc_selection' || match.draft_state === 'preparing') {
    throw new Error('Draft initialization did not complete')
  }
  if ((playersResult.data ?? []).length !== 2) {
    throw new Error('Draft initialization did not create both player states')
  }
  if (match.status === 'draft' && (!match.priority_player_id || match.current_draft_position < 1 || !revealedCharacters.length)) {
    throw new Error('Draft initialization returned incomplete state')
  }

  return {
    match,
    players: (playersResult.data ?? []) as OnlineMatchPlayer[],
    revealedCharacters,
    currentCharacter: revealedCharacters.find((card) => card.draft_position === match.current_draft_position) ?? null,
  }
}

export async function submitDraftBid(matchId: string, amount: number): Promise<void> {
  const { error } = await supabase.rpc('draft_bid', { p_match_id: matchId, p_amount: amount })
  if (error) throw error
}

export async function submitDraftPass(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('draft_pass', { p_match_id: matchId })
  if (error) throw error
}

export async function submitDraftFold(matchId: string): Promise<void> {
  const { error } = await supabase.rpc('draft_fold', { p_match_id: matchId })
  if (error) throw error
}
