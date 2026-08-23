import { supabase } from '../../../lib/supabase'

interface IdentifiableProfile {
  id: string
  is_system_player?: boolean
}

interface StateWithProfiles {
  yourProfile: IdentifiableProfile
  opponentProfile: IdentifiableProfile
}

export async function withSystemIdentity<T extends StateWithProfiles>(state: T): Promise<T> {
  const profileIds = [state.yourProfile.id, state.opponentProfile.id]
  const { data, error } = await supabase
    .from('profiles')
    .select('id, is_system_player')
    .in('id', profileIds)
  if (error) throw error

  const flags = new Map((data ?? []).map((profile) => [profile.id, profile.is_system_player]))
  return {
    ...state,
    yourProfile: {
      ...state.yourProfile,
      is_system_player: flags.get(state.yourProfile.id) ?? false,
    },
    opponentProfile: {
      ...state.opponentProfile,
      is_system_player: flags.get(state.opponentProfile.id) ?? false,
    },
  }
}
