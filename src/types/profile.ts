export type AvatarMode = 'google' | 'initial'

export interface PlayerIdentity {
  id: string
  username: string
  avatarUrl: string | null
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
}

export interface Profile {
  id: string
  username: string
  avatar_url: string | null
  avatar_mode: AvatarMode
  avatar_bg_color: string
  avatar_text_color: string
  username_changes_remaining: number
  is_guest: boolean
  is_admin: boolean
  is_system_player: boolean
  wins: number
  losses: number
  created_at: string
  boon_points: number
}

/** Safe profile shape for opponent/public multiplayer presentation. */
export type PublicGameProfile = Omit<Profile, 'boon_points'>
