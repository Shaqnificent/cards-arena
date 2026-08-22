import { useMemo, useState } from 'react'
import { AppHeader } from '../components/AppHeader'
import { LoadingScreen } from '../components/LoadingScreen'
import { useSuggestions } from '../features/suggestions/hooks/useSuggestions'
import type { SuggestionCategory, SuggestionInput, SuggestionSort, SuggestionStatus } from '../features/suggestions/types'
import type { Profile } from '../types/profile'

const categories: Array<[SuggestionCategory, string]> = [['gameplay','Gameplay'],['characters','Characters'],['verses','Verses'],['ui-ux','UI / UX'],['balance','Balance'],['bugs','Bugs'],['other','Other']]
const statuses: Array<[SuggestionStatus, string]> = [['submitted','Submitted'],['under_review','Under Review'],['planned','Planned'],['implemented','Implemented'],['declined','Declined']]

interface Props { currentUserId: string; profile: Profile; avatarUrl: string | null }

export function Suggestions({ currentUserId, profile, avatarUrl }: Props) {
  const board = useSuggestions(currentUserId)
  const [formOpen, setFormOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState<'all' | SuggestionCategory>('all')
  const [sort, setSort] = useState<SuggestionSort>('upvoted')
  const [form, setForm] = useState<SuggestionInput>({ title: '', description: '', category: 'gameplay' })
  const [formError, setFormError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const visible = useMemo(() => {
    const query = search.trim().toLowerCase()
    return board.suggestions.filter((item) => (category === 'all' || item.category === category) && (!query || item.title.toLowerCase().includes(query) || item.description.toLowerCase().includes(query)))
      .toSorted((a, b) => sort === 'upvoted' ? b.vote_count - a.vote_count || Date.parse(b.created_at) - Date.parse(a.created_at) : sort === 'newest' ? Date.parse(b.created_at) - Date.parse(a.created_at) : Date.parse(a.created_at) - Date.parse(b.created_at))
  }, [board.suggestions, category, search, sort])

  const submit = async () => {
    const input = { ...form, title: form.title.trim(), description: form.description.trim() }
    if (input.title.length < 3 || input.title.length > 120) return setFormError('Title must be between 3 and 120 characters.')
    if (input.description.length < 10 || input.description.length > 2000) return setFormError('Description must be between 10 and 2,000 characters.')
    setSubmitting(true); setFormError(null)
    try { await board.submit(input); setForm({ title: '', description: '', category: 'gameplay' }); setFormOpen(false) }
    catch (submitError) { console.error('Suggestion submission failed', submitError); setFormError('Unable to submit your suggestion.') }
    finally { setSubmitting(false) }
  }

  if (board.loading) return <LoadingScreen message="Loading suggestions..." />
  return <main className="suggestions-page"><AppHeader active="suggestions" username={profile.username} avatarUrl={avatarUrl} />
    <section className="suggestions-content"><header className="suggestions-hero"><div><p className="eyebrow">Community</p><h1>Suggestions</h1><p>Help shape Anime Arena. Share ideas, report issues, and vote on what should come next.</p></div><button className="button button-primary" onClick={() => setFormOpen(true)}>+ Submit Suggestion</button></header>
    {board.message && <p className="suggestions-message" role="status">{board.message}</p>}
    {formOpen && <section className="suggestion-form"><div className="suggestion-form-heading"><h2>Submit a Suggestion</h2><button type="button" onClick={() => setFormOpen(false)} aria-label="Close form">×</button></div>
      <label>Title<input maxLength={120} value={form.title} onChange={(event) => setForm({ ...form, title: event.target.value })} /></label>
      <label>Category<select value={form.category} onChange={(event) => setForm({ ...form, category: event.target.value as SuggestionCategory })}>{categories.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Description<textarea maxLength={2000} rows={6} value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} /></label>
      {formError && <p className="error-message" role="alert">{formError}</p>}<div className="suggestion-form-actions"><button className="button button-secondary" onClick={() => setFormOpen(false)}>Cancel</button><button className="button button-primary" disabled={submitting} onClick={() => void submit()}>{submitting ? 'Submitting...' : 'Submit Suggestion'}</button></div>
    </section>}
    <div className="suggestions-filters"><input aria-label="Search suggestions" type="search" placeholder="Search suggestions..." value={search} onChange={(event) => setSearch(event.target.value)} /><select aria-label="Filter by category" value={category} onChange={(event) => setCategory(event.target.value as 'all' | SuggestionCategory)}><option value="all">All Categories</option>{categories.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select><select aria-label="Sort suggestions" value={sort} onChange={(event) => setSort(event.target.value as SuggestionSort)}><option value="upvoted">Most Upvoted</option><option value="newest">Newest</option><option value="oldest">Oldest</option></select></div>
    {board.error ? <div className="catalogue-state"><h2>Unable to load suggestions.</h2><button className="button button-secondary" onClick={() => void board.refresh()}>Retry</button></div>
      : visible.length === 0 ? <div className="catalogue-state"><h2>{board.suggestions.length ? 'No suggestions match these filters.' : 'No suggestions yet.'}</h2><p>{board.suggestions.length ? 'Try clearing your search or category.' : 'Be the first to help shape Anime Arena.'}</p><button className="button button-primary" onClick={() => { setSearch(''); setCategory('all'); if (!board.suggestions.length) setFormOpen(true) }}>{board.suggestions.length ? 'Clear Filters' : 'Submit First Suggestion'}</button></div>
      : <div className="suggestions-list">{visible.map((item) => <article className="suggestion-card" key={item.id}><div className="suggestion-vote"><button className={item.current_user_voted ? 'voted' : ''} disabled={board.pendingId === item.id} onClick={() => void board.toggleVote(item)} aria-label={item.current_user_voted ? 'Remove upvote' : 'Upvote suggestion'}>▲</button><strong>{item.vote_count}</strong></div><div className="suggestion-body"><div className="suggestion-meta"><span>{categories.find(([value]) => value === item.category)?.[1]}</span>{profile.is_admin ? <select value={item.status} disabled={board.pendingId === item.id} onChange={(event) => void board.setStatus(item.id, event.target.value as SuggestionStatus)}>{statuses.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select> : <b className={`suggestion-status status-${item.status}`}>{statuses.find(([value]) => value === item.status)?.[1]}</b>}</div><h2>{item.title}</h2><p>{item.description}</p><small>Suggested by {item.author_username} • {new Date(item.created_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</small></div></article>)}</div>}
    </section>
  </main>
}
