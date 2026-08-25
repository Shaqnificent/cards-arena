import { useMemo, useState } from 'react'
import { AppHeader } from '../components/AppHeader'
import { LoadoutNav } from '../components/LoadoutNav'
import { BoonCard } from '../features/boons/components/BoonCard'
import { BoonRollDialog } from '../features/boons/components/BoonRollDialog'
import { useBoons } from '../features/boons/hooks/useBoons'
import { useActiveMatchBoon } from '../features/boons/hooks/useActiveMatchBoon'
import { ActiveMatchBoonLoading, ActiveMatchBoonNotice } from '../features/boons/components/ActiveMatchBoonNotice'
import type { BoonDefinition } from '../features/boons/types'
import type { Profile } from '../types/profile'

interface BoonsProps {
  profile: Profile
  avatarUrl: string | null
}

type RarityFilter = 'all' | BoonDefinition['rarity']
type EffectFilter = 'all' | 'overall' | 'power' | 'oc' | 'draft' | 'verse' | 'random'

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
  const equipped = boons.dashboard.boons.find((boon) => boon.equipped) ?? null
  const displayedPoints = boons.loading || boons.error ? profile.boon_points : boons.dashboard.boonPoints
  const busy = boons.pendingId !== null || boons.rolling || boons.resolvingId !== null
  const pendingRoll = boons.dashboard.pendingRoll
  const addedRoll = boons.rollResult?.status === 'added' ? boons.rollResult.roll : null
  const needsMorePoints = boons.dashboard.boonPoints < boons.dashboard.rollCost
  const poolExhausted = !needsMorePoints && !pendingRoll && !boons.dashboard.canRoll
  const [searchQuery, setSearchQuery] = useState('')
  const [rarityFilter, setRarityFilter] = useState<RarityFilter>('all')
  const [effectFilter, setEffectFilter] = useState<EffectFilter>('all')
  const normalizedSearch = searchQuery.trim().toLowerCase()
  const filtersActive = searchQuery.length > 0 || rarityFilter !== 'all' || effectFilter !== 'all'
  const filteredCatalogue = useMemo(() => boons.catalogue.filter((definition) => {
    const matchesSearch = !normalizedSearch || `${definition.name} ${definition.description} ${definition.key}`.toLowerCase().includes(normalizedSearch)
    const matchesRarity = rarityFilter === 'all' || definition.rarity === rarityFilter
    return matchesSearch && matchesRarity && matchesEffectFilter(definition, effectFilter)
  }), [boons.catalogue, effectFilter, normalizedSearch, rarityFilter])
  const clearFilters = () => {
    setSearchQuery('')
    setRarityFilter('all')
    setEffectFilter('all')
  }

  return <main className="boons-page">
    <AppHeader active="loadout" username={profile.username} avatarUrl={avatarUrl} />
    <div className="boon-content">
      <LoadoutNav active="boons" />
      <header className="boon-hero"><div><p className="eyebrow">Boon Shop</p><h1>Boons</h1><p>Spend Boon Points to discover reusable arena modifiers and manage your two-slot collection.</p></div><div className="boon-points-card"><span aria-hidden="true">✦</span><div><small>Boon Points</small><strong>{(eligible ? displayedPoints : 0).toLocaleString()} BP</strong></div></div></header>
      {matchBoon.loading && eligible ? <ActiveMatchBoonLoading /> : matchBoon.activeMatch && <ActiveMatchBoonNotice activeMatch={matchBoon.activeMatch} />}
      {matchBoon.error && <p className="boon-error error-message" role="alert">{matchBoon.error}</p>}

      {!eligible ? <section className="boon-unavailable" aria-labelledby="boon-unavailable-heading"><span aria-hidden="true">◇</span><h2 id="boon-unavailable-heading">{profile.is_system_player ? 'Player Boon Shop is unavailable' : 'Sign in to earn Boon Points and roll Boons'}</h2><p>{profile.is_system_player ? 'Administrator Boon behavior remains outside the player inventory system.' : 'Guest profiles do not participate in the persistent Boon economy.'}</p></section>
        : boons.loading ? <section className="boon-state" aria-live="polite"><span className="spinner" /><h2>Loading your Boon loadout...</h2></section>
          : <>
            {boons.error && <div className="boon-error error-message" role="alert"><span>{boons.error}</span><button className="button button-secondary" onClick={() => void boons.refresh()}>Retry</button></div>}

            <section className="boon-section" aria-labelledby="equipped-boon-heading"><div className="boon-section-heading"><div><p className="eyebrow">Active Loadout</p><h2 id="equipped-boon-heading">Equipped Boon</h2></div><small>Maximum 1</small></div>{equipped
              ? <div className="boon-equipped-slot"><BoonCard definition={equipped.definition} owned={equipped} summary /></div>
              : <div className="boon-empty-slot"><span aria-hidden="true">✦</span><div><strong>No Boon equipped</strong><p>You may keep your loadout empty or equip one from your inventory.</p></div></div>}
            </section>

            <section className="boon-section" aria-labelledby="owned-boons-heading"><div className="boon-section-heading"><div><p className="eyebrow">Your Collection</p><h2 id="owned-boons-heading">Your Boons</h2></div><strong>{boons.dashboard.inventoryCount} / {boons.dashboard.inventoryCapacity}<small> Inventory</small></strong></div>{boons.dashboard.boons.length === 0
              ? <div className="boon-empty-inventory"><h3>No Boons owned yet</h3><p>Roll below to discover your first Boon.</p></div>
              : <div className="boon-grid">{boons.dashboard.boons.map((boon) => <BoonCard key={boon.id} definition={boon.definition} owned={boon} pending={boons.pendingId === boon.id} actionsDisabled={busy} onEquip={() => void boons.equip(boon)} onUnequip={() => void boons.unequip(boon)} />)}</div>}
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
                <label className="boon-search-control"><span>Search</span><input type="search" value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Search Boons..." /></label>
                <label className="boon-filter-control"><span>Rarity</span><select value={rarityFilter} onChange={(event) => setRarityFilter(event.target.value as RarityFilter)}><option value="all">All Rarities</option><option value="common">Common</option><option value="rare">Rare</option><option value="epic">Epic</option><option value="legendary">Legendary</option></select></label>
                <label className="boon-filter-control"><span>Effect</span><select value={effectFilter} onChange={(event) => setEffectFilter(event.target.value as EffectFilter)}>{effectFilterOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
                {filtersActive && <button type="button" className="boon-clear-filters" onClick={clearFilters}>Clear Filters</button>}
              </div>
              {filteredCatalogue.length > 0
                ? <div className="boon-grid catalogue">{filteredCatalogue.map((definition) => <BoonCard key={definition.id} definition={definition} compact />)}</div>
                : <div className="boon-catalogue-empty" role="status"><span aria-hidden="true">◇</span><h3>No Boons Found</h3><p>Try changing your search or filters.</p><button type="button" className="button button-secondary" onClick={clearFilters}>Clear Filters</button></div>}
            </section>
          </>}
    </div>
    {addedRoll && <BoonRollDialog roll={addedRoll} mode="added" ownedBoons={boons.dashboard.boons} resolvingId={boons.resolvingId} onClose={boons.closeReveal} onReplace={() => undefined} onDiscard={() => undefined} />}
    {pendingRoll && boons.pendingDecisionOpen && <BoonRollDialog roll={pendingRoll} mode="pending" ownedBoons={boons.dashboard.boons} resolvingId={boons.resolvingId} onClose={boons.closePendingDecision} onReplace={(id) => void boons.resolve('replace', id)} onDiscard={() => void boons.resolve('discard')} />}
  </main>
}
