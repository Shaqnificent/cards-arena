export type SuggestionCategory = 'gameplay' | 'characters' | 'verses' | 'ui-ux' | 'balance' | 'bugs' | 'other'
export type SuggestionStatus = 'submitted' | 'under_review' | 'planned' | 'implemented' | 'declined'
export type SuggestionSort = 'upvoted' | 'newest' | 'oldest'

export interface Suggestion {
  id: string
  title: string
  description: string
  category: SuggestionCategory
  status: SuggestionStatus
  created_at: string
  author_id: string
  author_username: string
  vote_count: number
  current_user_voted: boolean
}

export interface SuggestionInput { title: string; description: string; category: SuggestionCategory }
