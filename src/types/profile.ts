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
}
