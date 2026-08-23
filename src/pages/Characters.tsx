import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { CharacterCard } from '../components/CharacterCard'
import { LoadingScreen } from '../components/LoadingScreen'
import { useCharacters } from '../hooks/useCharacters'
import { useVerses } from '../hooks/useVerses'

type CharacterSort = 'overall-desc' | 'overall-asc' | 'power-desc' | 'power-asc'

const characterSorts: CharacterSort[] = ['overall-desc', 'overall-asc', 'power-desc', 'power-asc']
const pageSize = 24

const getVerseFilterKey = (verse: { id: string; slug: string | null }) =>
  verse.slug?.trim() || `verse-${verse.id}`

interface CharactersProps { username: string; avatarUrl: string | null }

export function Characters({ username, avatarUrl }: CharactersProps) {
  const { characters, loading: charactersLoading, error: charactersError } = useCharacters()
  const { verses, loading: versesLoading, error: versesError } = useVerses()
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [searchParams, setSearchParams] = useSearchParams()
  const requestedVerse = searchParams.get('verse') ?? 'all'
  const requestedSort = searchParams.get('sort')
  const sort: CharacterSort = requestedSort && characterSorts.includes(requestedSort as CharacterSort)
    ? requestedSort as CharacterSort
    : 'overall-desc'
  const selectedVerseRecord = verses.find((verse) => getVerseFilterKey(verse) === requestedVerse)
  const selectedVerse = requestedVerse === 'all' || selectedVerseRecord
    ? requestedVerse
    : 'all'

  const filteredCharacters = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase()
    const visible = characters.filter((character) => {
      const matchesSearch = normalizedSearch.length === 0 ||
        character.name.toLowerCase().includes(normalizedSearch)
      const matchesVerse = selectedVerse === 'all' ||
        String(character.verse_id) === String(selectedVerseRecord?.id)
      return matchesSearch && matchesVerse
    })
    return visible.toSorted((a, b) => {
      if (sort === 'overall-desc') return b.overall - a.overall || b.power_score - a.power_score
      if (sort === 'overall-asc') return a.overall - b.overall || a.power_score - b.power_score
      if (sort === 'power-desc') return b.power_score - a.power_score || b.overall - a.overall
      return a.power_score - b.power_score || a.overall - b.overall
    })
  }, [characters, search, selectedVerse, selectedVerseRecord?.id, sort])

  const pageCount = Math.max(1, Math.ceil(filteredCharacters.length / pageSize))
  const currentPage = Math.min(page, pageCount)
  const paginatedCharacters = filteredCharacters.slice((currentPage - 1) * pageSize, currentPage * pageSize)

  const handleVerseChange = (slug: string) => {
    const next = new URLSearchParams(searchParams)
    if (slug === 'all') next.delete('verse'); else next.set('verse', slug)
    setSearchParams(next, { replace: true })
    setPage(1)
  }

  const handleSortChange = (nextSort: CharacterSort) => {
    const next = new URLSearchParams(searchParams)
    if (nextSort === 'overall-desc') next.delete('sort'); else next.set('sort', nextSort)
    setSearchParams(next, { replace: true })
    setPage(1)
  }

  if (charactersLoading || versesLoading) {
    return <LoadingScreen message="Loading the playable roster..." />
  }

  const error = charactersError ?? versesError

  return (
    <main className="catalogue-page">
      <AppHeader active="characters" username={username} avatarUrl={avatarUrl} />

      <section className="catalogue-content" aria-labelledby="characters-heading">
        <div className="catalogue-hero">
          <div><p className="eyebrow">Playable Roster</p><h1 id="characters-heading">Characters</h1>
            <p className="catalogue-intro">Browse all fighters currently available in Anime Arena.</p></div>
          <div className="fighter-count" aria-label={`${characters.length} active fighters`}><span aria-hidden="true">♟</span><strong>{characters.length}</strong><small>Fighters</small></div>
        </div>

        <div className="catalogue-controls">
          <label className="field">
            <span className="sr-only">Search characters</span>
            <input
              type="search"
              value={search}
              onChange={(event) => { setSearch(event.target.value); setPage(1) }}
              placeholder="Search characters..."
            />
          </label>
          <label className="field">
            <span className="sr-only">Filter by verse</span>
            <select value={selectedVerse} onChange={(event) => handleVerseChange(event.target.value)}>
              <option value="all">All Verses</option>
              {verses.map((verse) => <option key={verse.id} value={getVerseFilterKey(verse)}>{verse.name}</option>)}
            </select>
          </label>
          <label className="field">
            <span className="sr-only">Sort characters</span>
            <select value={sort} onChange={(event) => handleSortChange(event.target.value as CharacterSort)}>
              <option value="overall-desc">Overall: High → Low</option>
              <option value="overall-asc">Overall: Low → High</option>
              <option value="power-desc">Power Score: High → Low</option>
              <option value="power-asc">Power Score: Low → High</option>
            </select>
          </label>
        </div>

        <div className="verse-chips" aria-label="Quick verse filters">
          <button type="button" className={selectedVerse === 'all' ? 'active' : ''} onClick={() => handleVerseChange('all')}>All</button>
          {verses.map((verse) => {
            const verseKey = getVerseFilterKey(verse)
            return <button type="button" key={verse.id} className={selectedVerse === verseKey ? 'active' : ''} onClick={() => handleVerseChange(verseKey)}>{verse.name}</button>
          })}
        </div>

        <div className="rating-info"><span aria-hidden="true">ⓘ</span><p><strong>OVR</strong> = strength within their verse <i>•</i> <strong>Global Power</strong> = cross-verse tiebreaker (used only when OVR is equal)</p></div>

        {error ? (
          <div className="catalogue-state error-message" role="alert">
            Unable to load the character catalogue: {error}
          </div>
        ) : (
          <>
            {(search || selectedVerse !== 'all') && <p className="character-count">{filteredCharacters.length} {filteredCharacters.length === 1 ? 'Result' : 'Results'}</p>}
            {characters.length === 0 ? (
              <div className="catalogue-state">
                <h2>No roster data available</h2>
                <p>No active characters have been added yet.</p>
              </div>
            ) : filteredCharacters.length > 0 ? (
              <div className="character-grid">
                {paginatedCharacters.map((character) => <CharacterCard key={character.id} character={character} />)}
              </div>
            ) : (
              <div className="catalogue-state">
                <h2>No fighters found</h2>
                <p>Try a different character name or verse.</p>
              </div>
            )}
            {filteredCharacters.length > pageSize && <nav className="catalogue-pagination" aria-label="Character pages">
              <button type="button" aria-label="Previous page" disabled={currentPage === 1} onClick={() => setPage((value) => Math.max(1, value - 1))}>‹</button>
              {Array.from({ length: pageCount }, (_, index) => index + 1).map((pageNumber) => <button type="button" key={pageNumber} className={pageNumber === currentPage ? 'active' : ''} aria-current={pageNumber === currentPage ? 'page' : undefined} onClick={() => setPage(pageNumber)}>{pageNumber}</button>)}
              <button type="button" aria-label="Next page" disabled={currentPage === pageCount} onClick={() => setPage((value) => Math.min(pageCount, value + 1))}>›</button>
            </nav>}
          </>
        )}
      </section>
    </main>
  )
}
