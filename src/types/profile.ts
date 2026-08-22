export interface Profile {
  id: string
  username: string
  avatar_url: string | null
  is_guest: boolean
  wins: number
  losses: number
  created_at: string
}
