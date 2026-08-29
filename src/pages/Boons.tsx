import { useEffect, useMemo, useState } from 'react'
import { AppHeader } from '../components/AppHeader'
import { LoadoutNav } from '../components/LoadoutNav'
import { BoonCard } from '../features/boons/components/BoonCard'
import { BoonRollDialog } from '../features/boons/components/BoonRollDialog'
import { useBoons } from '../features/boons/hooks/useBoons'
import { useActiveMatchBoon } from '../features/boons/hooks/useActiveMatchBoon'
import { ActiveMatchBoonLoading, ActiveMatchBoonNotice } from '../features/boons/components/ActiveMatchBoonNotice'
import type { BoonDefinition } from '../features/boons/types'
import type { Profile } from '../types/profile'
import { getPaginationItems } from '../lib/pagination'

interface BoonsProps {
  profile: Profile
  avatarUrl: string | null
}

type RarityFilter = 'all' | BoonDefinition['rarity']
type EffectFilter = 'all' | 'overall' | 'power' | 'oc' | 'draft' | 'verse' | 'random'
const cataloguePageSize = 12

const getResponsiveSiblingCount = () => {
  if (typeof window === 'undefined') return 3
  if (window.matchMedia('(max-width: 520px)').matches) return 1
  if (window.matchMedia('(max-width: 900px)').matches) return 2
  return 3
}

const effectFilterOptions: ReadonlyArray<{ value: EffectFilter; label: string }> = [
  { value: 'all', label: 'All Effects' },
  { value: 'overall', label: 'OVR Boost' },
  { value: 'power', label: 'Power Boost' },
  { value: 'oc', label: 'OC Boost' },
  { value: 'draft', label: 'Draft Fighter Boost' },
  { value: 'verse', label: 'Team / Verse Boost' },
  { value: 'random', label: 'Random Effect' },
]

function matchesEffectFilter(definition: BoonDefinition, filter: EffectFilter): boolean {
  if (filter === 'all') return true
  const effectType = definition.effectType.toLowerCase()
  const targetRule = definition.targetRule.toLowerCase()
  const combined = `${effectType} ${targetRule}`
  if (filter === 'overall') return combined.includes('overall') || combined.includes('ovr')
  if (filter === 'power') return combined.includes('power')
  if (filter === 'oc') return effectType.startsWith('oc_') || targetRule.includes('selected_oc')
  if (filter === 'draft') return /draft|canon|lowest|highest|multi/.test(combined)
  if (filter === 'verse') return combined.includes('verse')
  return combined.includes('random')
}

export function Boons({ profile, avatarUrl }: BoonsProps) {
  const eligible = !profile.is_guest && !profile.is_system_player
  const boons = useBoons(eligible)
  const matchBoon = useActiveMatchBoon(eligible)
  const displayedPoints = boons.loading || boons.error ? profile.boon_points : boons.dashboard.boonPoints
  const busy = boons.pendingId !== null || boons.rolling || boons.resolvingId !== null
  const pendingRoll = boons.dashboard.pendingRoll
  const addedRoll = boons.rollResult?.status === 'added' ? boons.rollResult.roll : null
  const dialogRoll = addedRoll ?? (pendingRoll && boons.pendingDecisionOpen ? pendingRoll : null)
  const dialogMode = boons.rollResult?.status ?? 'pending'
  const needsMorePoints = boons.dashboard.boonPoints < boons.dashboard.rollCost
  const poolExhausted = !needsMorePoints && !pendingRoll && !boons.dashboard.canRoll
  const [searchQuery, setSearchQuery] = useState('')
  const [rarityFilter, setRarityFilter] = useState<RarityFilter>('all')
  const [effectFilter, setEffectFilter] = useState<EffectFilter>('all')
  const [cataloguePage, setCataloguePage] = useState(1)
  const [paginationSiblingCount, setPaginationSiblingCount] = useState(getResponsiveSiblingCount)
  const normalizedSearch = searchQuery.trim().toLowerCase()
  const filtersActive = searchQuery.length > 0 || rarityFilter !== 'all' || effectFilter !== 'all'
  const filteredCatalogue = useMemo(() => boons.catalogue.filter((definition) => {
    const matchesSearch = !normalizedSearch || `${definition.name} ${definition.description} ${definition.key}`.toLowerCase().includes(normalizedSearch)
    const matchesRarity = rarityFilter === 'all' || definition.rarity === rarityFilter
    return matchesSearch && matchesRarity && matchesEffectFilter(definition, effectFilter)
  }), [boons.catalogue, effectFilter, normalizedSearch, rarityFilter])
  const cataloguePageCount = Math.max(1, Math.ceil(filteredCatalogue.length / cataloguePageSize))
  const currentCataloguePage = Math.min(cataloguePage, cataloguePageCount)
  const paginatedCatalogue = filteredCatalogue.slice(
    (currentCataloguePage - 1) * cataloguePageSize,
    currentCataloguePage * cataloguePageSize,
  )
  const paginationItems = useMemo(() => getPaginationItems({
    currentPage: currentCataloguePage,
    totalPages: cataloguePageCount,
    siblingCount: paginationSiblingCount,
  }), [cataloguePageCount, currentCataloguePage, paginationSiblingCount])

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

  const clearFilters = () => {
    setSearchQuery('')
    setRarityFilter('all')
    setEffectFilter('all')
    setCataloguePage(1)
  }

  return <main className="boons-page">
    <AppHeader active="loadout" username={profile.username} avatarUrl={avatarUrl} avatarMode={profile.avatar_mode} avatarBgColor={profile.avatar_bg_color} avatarTextColor={profile.avatar_text_color} profileId={!profile.is_guest && !profile.is_system_player ? profile.id : undefined} />
    <div className="boon-content">
      <LoadoutNav active="boons" />
      <header className="boon-hero"><div><p className="eyebrow">Boon Shop</p><h1>Boons</h1><p>Spend Boon Points to discover reusable arena modifiers and manage your two-slot collection.</p></div><div className="boon-points-card"><span aria-hidden="true">✦</span><div><small>Boon Points</small><strong>{(eligible ? displayedPoints : 0).toLocaleString()} BP</strong></div></div></header>
      {matchBoon.loading && eligible ? <ActiveMatchBoonLoading /> : matchBoon.activeMatch && <ActiveMatchBoonNotice activeMatch={matchBoon.activeMatch} />}
      {matchBoon.error && <p className="boon-error error-message" role="alert">{matchBoon.error}</p>}

      {!eligible ? <section className="boon-unavailable" aria-labelledby="boon-unavailable-heading"><span aria-hidden="true">◇</span><h2 id="boon-unavailable-heading">{profile.is_system_player ? 'Player Boon Shop is unavailable' : 'Sign in to earn Boon Points and roll Boons'}</h2><p>{profile.is_system_player ? 'Administrator Boon behavior remains outside the player inventory system.' : 'Guest profiles do not participate in the persistent Boon economy.'}</p></section>
        : boons.loading ? <section className="boon-state" aria-live="polite"><span className="spinner" /><h2>Loading your Boon loadout...</h2></section>
          : <>
            {boons.error && <div className="boon-error error-message" role="alert"><span>{boons.error}</span><button className="button button-secondary" onClick={() => void boons.refresh()}>Retry</button></div>}

            <section className="boon-section boon-owned-section" aria-labelledby="owned-boons-heading"><div className="boon-section-heading"><div><p className="eyebrow">Your Boons</p><h2 id="owned-boons-heading">Your Boons</h2></div><strong>{boons.dashboard.inventoryCount} / {boons.dashboard.inventoryCapacity}<small> Owned</small></strong></div>{boons.dashboard.boons.length === 0
              ? <div className="boon-empty-inventory"><h3>No Boons owned yet</h3><p>Roll below to discover your first Boon.</p></div>
              : <div className="boon-owned-grid">{boons.dashboard.boons.map((boon) => <BoonCard key={boon.id} definition={boon.definition} owned={boon} pending={boons.pendingId === boon.id} actionsDisabled={busy} onEquip={() => void boons.equip(boon)} onUnequip={() => void boons.unequip(boon)} />)}</div>}
            </section>

            <section className="boon-roll-shop" aria-labelledby="roll-boon-heading">
              <div className="boon-roll-copy"><span aria-hidden="true">✦</span><div><p className="eyebrow">Boon Shop</p><h2 id="roll-boon-heading">Roll a Boon</h2><p>Results are selected securely from active Boons you do not already own.</p></div></div>
              <div className="boon-roll-purchase">
                <div><small>Roll Cost</small><strong>{boons.dashboard.rollCost.toLocaleString()} BP</strong></div>
                {pendingRoll ? <button type="button" className="button button-primary" disabled={busy} onClick={boons.openPendingDecision}>Resolve Pending Roll</button>
                  : <button type="button" className="button button-primary" disabled={!boons.dashboard.canRoll || busy} onClick={() => void boons.roll()}>{boons.rolling ? 'Rolling...' : 'Roll'}</button>}
              </div>
              {pendingRoll ? <button type="button" className="boon-pending-notice" onClick={boons.openPendingDecision}><strong>Pending decision</strong><span>{pendingRoll.definition.name} is waiting. Replace an owned Boon or discard the new result.</span></button>
                : needsMorePoints ? <p className="boon-roll-status"><strong>{boons.dashboard.boonPoints.toLocaleString()} / {boons.dashboard.rollCost.toLocaleString()} BP</strong><span>Play ranked matches to earn more Boon Points.</span></p>
                  : poolExhausted ? <p className="boon-roll-status"><strong>No new Boons are currently available.</strong><span>You already own every eligible result in the active pool.</span></p>
                    : <p className="boon-roll-status ready"><strong>{boons.dashboard.boonPoints.toLocaleString()} BP available</strong><span>{boons.dashboard.inventoryCount === 2 ? 'Your inventory is full; a roll will create a replacement decision.' : 'A new result will be added to your inventory unequipped.'}</span></p>}
            </section>

            <section className="boon-section boon-catalogue" aria-labelledby="boon-catalogue-heading">
              <div className="boon-section-heading"><div><p className="eyebrow">Active Catalogue</p><h2 id="boon-catalogue-heading">Discover Boons</h2></div><small aria-live="polite">{filtersActive ? `${filteredCatalogue.length} of ${boons.catalogue.length}` : `${boons.catalogue.length} Available`}</small></div>
              <div className="boon-catalogue-toolbar" role="search" aria-label="Filter the Boon catalogue">
                <label className="boon-search-control"><span>Search</span><input type="search" value={searchQuery} onChange={(event) => { setSearchQuery(event.target.value); setCataloguePage(1) }} placeholder="Search Boons..." /></label>
                <label className="boon-filter-control"><span>Rarity</span><select value={rarityFilter} onChange={(event) => { setRarityFilter(event.target.value as RarityFilter); setCataloguePage(1) }}><option value="all">All Rarities</option><option value="common">Common</option><option value="rare">Rare</option><option value="epic">Epic</option><option value="legendary">Legendary</option><option value="mythic">Mythic</option></select></label>
                <label className="boon-filter-control"><span>Effect</span><select value={effectFilter} onChange={(event) => { setEffectFilter(event.target.value as EffectFilter); setCataloguePage(1) }}>{effectFilterOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
                {filtersActive && <button type="button" className="boon-clear-filters" onClick={clearFilters}>Clear Filters</button>}
              </div>
              {filteredCatalogue.length > 0
                ? <>
                  <div className="boon-grid catalogue">{paginatedCatalogue.map((definition) => <BoonCard key={definition.id} definition={definition} compact />)}</div>
                  {filteredCatalogue.length > cataloguePageSize && <nav className="catalogue-pagination" aria-label="Boon catalogue pages">
                    <button type="button" aria-label="Previous page" disabled={currentCataloguePage === 1} onClick={() => setCataloguePage((value) => Math.max(1, value - 1))}>‹</button>
                    {paginationItems.map((item) => typeof item === 'number'
                      ? <button type="button" key={item} className={item === currentCataloguePage ? 'active' : ''} aria-current={item === currentCataloguePage ? 'page' : undefined} aria-label={`Page ${item}`} onClick={() => setCataloguePage(item)}>{item}</button>
                      : <span className="catalogue-pagination-ellipsis" key={item} aria-hidden="true">&hellip;</span>)}
                    <button type="button" aria-label="Next page" disabled={currentCataloguePage === cataloguePageCount} onClick={() => setCataloguePage((value) => Math.min(cataloguePageCount, value + 1))}>›</button>
                  </nav>}
                </>
                : <div className="boon-catalogue-empty" role="status"><span aria-hidden="true">◇</span><h3>No Boons Found</h3><p>Try changing your search or filters.</p><button type="button" className="button button-secondary" onClick={clearFilters}>Clear Filters</button></div>}
            </section>
          </>}
    </div>
    {(boons.rolling || dialogRoll) && <BoonRollDialog roll={dialogRoll} mode={dialogMode} animateReveal={boons.rolling || Boolean(boons.rollResult)} ownedBoons={boons.dashboard.boons} resolvingId={boons.resolvingId} onClose={dialogMode === 'added' ? boons.closeReveal : boons.closePendingDecision} onReplace={(id) => void boons.resolve('replace', id)} onDiscard={() => void boons.resolve('discard')} />}
  </main>
}
