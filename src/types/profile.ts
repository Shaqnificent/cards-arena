export interface Profile {
  id: string
  username: string
  avatar_url: string | null
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
