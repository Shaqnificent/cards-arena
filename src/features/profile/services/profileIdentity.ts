import { supabase } from '../../../lib/supabase'
import type { AvatarMode } from '../../../types/profile'
import type { ProfileIdentityUpdate } from '../avatarIdentity'

export type UsernameAvailabilityStatus = 'available' | 'current' | 'invalid' | 'reserved' | 'taken'

export interface UsernameAvailability {
  available: boolean
  status: UsernameAvailabilityStatus
  normalizedUsername: string
}

export async function checkUsernameAvailability(username: string): Promise<UsernameAvailability> {
  const { data, error } = await supabase.rpc('check_username_availability', { p_username: username })
  if (error) throw error
  return data as unknown as UsernameAvailability
}

export async function updateProfileIdentity(input: {
  username: string
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
}): Promise<ProfileIdentityUpdate> {
  const { data, error } = await supabase.rpc('update_profile_identity', {
    p_username: input.username,
    p_avatar_mode: input.avatarMode,
    p_avatar_bg_color: input.avatarBgColor,
    p_avatar_text_color: input.avatarTextColor,
  })
  if (error) throw error
  return data as unknown as ProfileIdentityUpdate
}
