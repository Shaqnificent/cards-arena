import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { CharacterCard } from '../components/CharacterCard'
import { LoadingScreen } from '../components/LoadingScreen'
import { useCharacters } from '../hooks/useCharacters'
import type { CharacterVerse } from '../types/verse'
import { getPaginationItems } from '../lib/pagination'
import type { AvatarMode } from '../types/profile'

type CharacterSort = 'overall-desc' | 'overall-asc' | 'power-desc' | 'power-asc'

const characterSorts: CharacterSort[] = ['overall-desc', 'overall-asc', 'power-desc', 'power-asc']
const pageSize = 24

const getLegacyVerseFilterKey = (verse: { id: number; slug: string | null }) =>
  verse.slug?.trim() || `verse-${verse.id}`

interface CharactersProps { username: string; avatarUrl: string | null; avatarMode: AvatarMode; avatarBgColor: string; avatarTextColor: string; profileId?: string }

const getResponsiveSiblingCount = () => {
  if (typeof window === 'undefined') return 3
  if (window.matchMedia('(max-width: 520px)').matches) return 1
  if (window.matchMedia('(max-width: 900px)').matches) return 2
  return 3
}

export function Characters({ username, avatarUrl, avatarMode, avatarBgColor, avatarTextColor, profileId }: CharactersProps) {
  const { characters, loading: charactersLoading, error: charactersError } = useCharacters()
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [paginationSiblingCount, setPaginationSiblingCount] = useState(getResponsiveSiblingCount)
  const [searchParams, setSearchParams] = useSearchParams()
  const requestedVerse = searchParams.get('verse')
  const requestedSort = searchParams.get('sort')
  const sort: CharacterSort = requestedSort && characterSorts.includes(requestedSort as CharacterSort)
    ? requestedSort as CharacterSort
    : 'overall-desc'
  const catalogueVerses = useMemo(() => {
    const versesById = new Map<string, CharacterVerse>()
    for (const character of characters) {
      if (character.verses) versesById.set(String(character.verse_id), character.verses)
    }
    return [...versesById.values()].toSorted((first, second) =>
      first.name.localeCompare(second.name, undefined, { sensitivity: 'base' }))
  }, [characters])
  const selectedVerseRecord = requestedVerse
    ? catalogueVerses.find((verse) =>
        String(verse.id) === requestedVerse || getLegacyVerseFilterKey(verse) === requestedVerse)
    : undefined
  const selectedVerseId = selectedVerseRecord ? String(selectedVerseRecord.id) : 'all'

  const filteredCharacters = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase()
    const visible = characters.filter((character) => {
      const matchesSearch = normalizedSearch.length === 0 ||
        character.name.toLowerCase().includes(normalizedSearch)
      const matchesVerse = selectedVerseId === 'all' || String(character.verse_id) === selectedVerseId
      return matchesSearch && matchesVerse
    })
    return visible.toSorted((a, b) => {
      if (sort === 'overall-desc') return b.overall - a.overall || b.power_score - a.power_score
      if (sort === 'overall-asc') return a.overall - b.overall || a.power_score - b.power_score
      if (sort === 'power-desc') return b.power_score - a.power_score || b.overall - a.overall
      return a.power_score - b.power_score || a.overall - b.overall
    })
  }, [characters, search, selectedVerseId, sort])

  const pageCount = Math.max(1, Math.ceil(filteredCharacters.length / pageSize))
  const currentPage = Math.min(page, pageCount)
  const paginatedCharacters = filteredCharacters.slice((currentPage - 1) * pageSize, currentPage * pageSize)
  const paginationItems = useMemo(() => getPaginationItems({
    currentPage,
    totalPages: pageCount,
    siblingCount: paginationSiblingCount,
  }), [currentPage, pageCount, paginationSiblingCount])

  useEffect(() => {
    const mobileQuery = window.matchMedia('(max-width: 520px)')
    const tabletQuery = window.matchMedia('(max-width: 900px)')
    const updateSiblingCount = () => setPaginationSiblingCount(
      mobileQuery.matches ? 1 : tabletQuery.matches ? 2 : 3)
    mobileQuery.addEventListener('change', updateSiblingCount)
    tabletQuery.addEventListener('change', updateSiblingCount)
    return () => {
      mobileQuery.removeEventListener('change', updateSiblingCount)
      tabletQuery.removeEventListener('change', updateSiblingCount)
    }
  }, [])

  const handleVerseChange = (verseId: string) => {
    const next = new URLSearchParams(searchParams)
    if (verseId === 'all') next.delete('verse'); else next.set('verse', verseId)
    setSearchParams(next, { replace: true })
    setPage(1)
  }

  const handleSortChange = (nextSort: CharacterSort) => {
    const next = new URLSearchParams(searchParams)
    if (nextSort === 'overall-desc') next.delete('sort'); else next.set('sort', nextSort)
    setSearchParams(next, { replace: true })
    setPage(1)
  }

  if (charactersLoading) {
    return <LoadingScreen message="Loading the playable roster..." />
  }

  const error = charactersError

  return (
    <main className="catalogue-page">
      <AppHeader active="characters" username={username} avatarUrl={avatarUrl} avatarMode={avatarMode} avatarBgColor={avatarBgColor} avatarTextColor={avatarTextColor} profileId={profileId} />

      <section className="catalogue-content" aria-labelledby="characters-heading">
        <div className="catalogue-hero">
          <div>
            <p className="eyebrow">Playable Roster</p>
            <h1 id="characters-heading">Characters</h1>
            <p className="catalogue-intro">Browse all fighters currently available in Anime Arena.</p>
          </div>
          <div className="fighter-count" aria-label={`${characters.length} fighters`}>
            <span aria-hidden="true">♟</span>
            <strong>{characters.length}</strong>
            <small>Fighters</small>
          </div>
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
            <select value={selectedVerseId} onChange={(event) => handleVerseChange(event.target.value)}>
              <option value="all">All Verses</option>
              {catalogueVerses.map((verse) => <option key={verse.id} value={String(verse.id)}>{verse.name}</option>)}
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
          <button type="button" className={selectedVerseId === 'all' ? 'active' : ''} onClick={() => handleVerseChange('all')}>All</button>
          {catalogueVerses.map((verse) => {
            const verseId = String(verse.id)
            return <button type="button" key={verse.id} className={selectedVerseId === verseId ? 'active' : ''} onClick={() => handleVerseChange(verseId)}>{verse.name}</button>
          })}
        </div>

        <div className="rating-info"><span aria-hidden="true">ⓘ</span><p><strong>OVR</strong> = strength within their verse <i>•</i> <strong>Global Power</strong> = cross-verse tiebreaker (used only when OVR is equal)</p></div>

        {error ? (
          <div className="catalogue-state error-message" role="alert">
            Unable to load the character catalogue: {error}
          </div>
        ) : (
          <>
            {(search || selectedVerseId !== 'all') && <p className="character-count">{filteredCharacters.length} {filteredCharacters.length === 1 ? 'Result' : 'Results'}</p>}
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
              {paginationItems.map((item) => typeof item === 'number'
                ? <button type="button" key={item} className={item === currentPage ? 'active' : ''} aria-current={item === currentPage ? 'page' : undefined} aria-label={`Page ${item}`} onClick={() => setPage(item)}>{item}</button>
                : <span className="catalogue-pagination-ellipsis" key={item} aria-hidden="true">&hellip;</span>)}
              <button type="button" aria-label="Next page" disabled={currentPage === pageCount} onClick={() => setPage((value) => Math.min(pageCount, value + 1))}>›</button>
            </nav>}
          </>
        )}
      </section>
    </main>
  )
}
