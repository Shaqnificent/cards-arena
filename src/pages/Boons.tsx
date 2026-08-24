import { AppHeader } from '../components/AppHeader'
import { BoonCard } from '../features/boons/components/BoonCard'
import { useBoons } from '../features/boons/hooks/useBoons'
import type { Profile } from '../types/profile'

interface BoonsProps {
  profile: Profile
  avatarUrl: string | null
}

export function Boons({ profile, avatarUrl }: BoonsProps) {
  const eligible = !profile.is_guest && !profile.is_system_player
  const boons = useBoons(eligible)
  const equipped = boons.dashboard.boons.find((boon) => boon.equipped) ?? null
  const displayedPoints = boons.loading || boons.error ? profile.boon_points : boons.dashboard.boonPoints

  return <main className="boons-page">
    <AppHeader active="boons" username={profile.username} avatarUrl={avatarUrl} />
    <div className="boon-content">
      <header className="boon-hero"><div><p className="eyebrow">Strategic Loadout</p><h1>Boons</h1><p>Manage reusable arena modifiers before they become available in ranked matches.</p></div><div className="boon-points-card"><span aria-hidden="true">✦</span><div><small>Boon Points</small><strong>{(eligible ? displayedPoints : 0).toLocaleString()} BP</strong></div></div></header>

      {!eligible ? <section className="boon-unavailable" aria-labelledby="boon-unavailable-heading"><span aria-hidden="true">◇</span><h2 id="boon-unavailable-heading">{profile.is_system_player ? 'Player Boon loadouts are unavailable' : 'Sign in to build a Boon loadout'}</h2><p>{profile.is_system_player ? 'Administrator Boon behavior remains outside the player inventory system.' : 'Guest profiles do not participate in persistent Boon inventory.'}</p></section>
        : boons.loading ? <section className="boon-state" aria-live="polite"><span className="spinner" /><h2>Loading your Boon loadout...</h2></section>
          : <>
            {boons.error && <div className="boon-error error-message" role="alert"><span>{boons.error}</span><button className="button button-secondary" onClick={() => void boons.refresh()}>Retry</button></div>}

            <section className="boon-section" aria-labelledby="equipped-boon-heading"><div className="boon-section-heading"><div><p className="eyebrow">Active Loadout</p><h2 id="equipped-boon-heading">Equipped Boon</h2></div><small>Maximum 1</small></div>{equipped
              ? <div className="boon-equipped-slot"><BoonCard definition={equipped.definition} owned={equipped} pending={boons.pendingId === equipped.id} actionsDisabled={boons.pendingId !== null} onUnequip={() => void boons.unequip(equipped)} /></div>
              : <div className="boon-empty-slot"><span aria-hidden="true">✦</span><div><strong>No Boon equipped</strong><p>You may keep your loadout empty or equip one from your inventory.</p></div></div>}
            </section>

            <section className="boon-section" aria-labelledby="owned-boons-heading"><div className="boon-section-heading"><div><p className="eyebrow">Your Collection</p><h2 id="owned-boons-heading">Your Boons</h2></div><strong>{boons.dashboard.inventoryCount} / {boons.dashboard.inventoryCapacity}<small> Inventory</small></strong></div>{boons.dashboard.boons.length === 0
              ? <div className="boon-empty-inventory"><h3>No Boons owned yet</h3><p>Boons will be obtainable from the Boon Shop in the next phase.</p></div>
              : <div className="boon-grid">{boons.dashboard.boons.map((boon) => <BoonCard key={boon.id} definition={boon.definition} owned={boon} pending={boons.pendingId === boon.id} actionsDisabled={boons.pendingId !== null} onEquip={() => void boons.equip(boon)} onUnequip={() => void boons.unequip(boon)} />)}</div>}
            </section>

            <section className="boon-shop-placeholder"><span aria-hidden="true">◇</span><div><p className="eyebrow">Coming Next</p><h2>Boon Shop</h2><p>Rolling and spending Boon Points will be added in Phase 3.</p></div></section>

            <section className="boon-section boon-catalogue" aria-labelledby="boon-catalogue-heading"><div className="boon-section-heading"><div><p className="eyebrow">Active Catalogue</p><h2 id="boon-catalogue-heading">Discover Boons</h2></div><small>{boons.catalogue.length} Available</small></div><div className="boon-grid catalogue">{boons.catalogue.map((definition) => <BoonCard key={definition.id} definition={definition} compact />)}</div></section>
          </>}
    </div>
  </main>
}
