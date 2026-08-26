import { supabase } from '../../../lib/supabase'
import type { PublicPlayerProfile } from '../types'

export async function getPublicPlayerProfile(playerId: string): Promise<PublicPlayerProfile | null> {
  const { data, error } = await supabase.rpc('get_public_player_profile', {
    p_player_id: playerId,
  })
  if (error) throw error
  if (!data) return null

  const payload = data as unknown as Record<string, unknown>
  const identityDefaults = {
    avatarMode: payload.avatarMode === 'initial' ? 'initial' as const : 'google' as const,
    avatarBgColor: typeof payload.avatarBgColor === 'string' ? payload.avatarBgColor : '#7C3AED',
    avatarTextColor: typeof payload.avatarTextColor === 'string' ? payload.avatarTextColor : '#FFFFFF',
    usernameChangesRemaining: typeof payload.usernameChangesRemaining === 'number' ? payload.usernameChangesRemaining : null,
  }
  if (Array.isArray(payload.ocFamily)) {
    return {
      ...(payload as unknown as Omit<PublicPlayerProfile, 'ocFamily'>),
      ...identityDefaults,
      ocFamily: {
        name: null,
        tagline: null,
        description: null,
        logoPath: null,
        updatedAt: null,
        members: payload.ocFamily as PublicPlayerProfile['ocFamily']['members'],
      },
    }
  }

  return { ...(data as PublicPlayerProfile), ...identityDefaults }
}
