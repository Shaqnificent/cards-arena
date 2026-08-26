import { Link } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { OCImage } from '../features/ocs/components/OCImage'
import { useLoadoutSummary } from '../features/loadout/hooks/useLoadoutSummary'
import { useActiveMatchBoon } from '../features/boons/hooks/useActiveMatchBoon'
import { ActiveMatchBoonLoading, ActiveMatchBoonNotice } from '../features/boons/components/ActiveMatchBoonNotice'
import type { Profile } from '../types/profile'

export function Loadout({ profile, avatarUrl }: { profile: Profile; avatarUrl: string | null }) {
  const boonEligible = !profile.is_guest && !profile.is_system_player
  const summary = useLoadoutSummary({ boonEligible, systemProfile: profile.is_system_player })
  const matchBoon = useActiveMatchBoon(boonEligible)
  const equippedBoon = summary.boonDashboard?.boons.find((boon) => boon.equipped) ?? null

  return <main className="loadout-page">
    <AppHeader active="loadout" username={profile.username} avatarUrl={avatarUrl} />
    <section className="loadout-content" aria-labelledby="loadout-heading">
      <header className="loadout-hero">
        <p className="eyebrow">Pre-Match Build</p>
        <h1 id="loadout-heading">Your Loadout</h1>
        <p>Prepare your persistent OC Family and tactical Boon before entering ranked matches.</p>
      </header>

      {profile.is_system_player ? <section className="loadout-unavailable">
        <span aria-hidden="true">◇</span>
        <h2>Player Loadout management is unavailable</h2>
        <p>The Administrator uses system-controlled match behavior rather than a player inventory.</p>
      </section> : <div className="loadout-summary-grid">
        <article className="loadout-summary-card oc-summary-card">
          <header><div><p className="eyebrow">Persistent Fighters</p><h2>OC Family</h2></div><strong>{summary.ocLoading ? '—' : `${summary.ocMembers.length} / 3`}<small> Equipped</small></strong></header>
          {summary.ocLoading ? <p className="loadout-card-state">Loading your OC Family...</p>
            : summary.ocError ? <div className="loadout-card-state error" role="alert"><span>{summary.ocError}</span><button type="button" className="text-button" onClick={() => void summary.refresh()}>Try again</button></div>
              : summary.ocMembers.length > 0 ? <div className="loadout-portraits">{summary.ocMembers.map((member) => <div key={member.id}><OCImage src={member.image_url} name={member.name} /><span>{member.name}</span></div>)}</div>
                : <div className="loadout-card-empty"><strong>No OC Family equipped</strong><p>Create or equip fighters to prepare your possible match selections.</p></div>}
          <p className="loadout-card-description">Manage your OCs, progression, portraits, lore, and active Family.</p>
          <Link className="button button-primary" to="/ocs">Manage</Link>
        </article>

        <article className="loadout-summary-card boon-summary-card">
          <header><div><p className="eyebrow">Tactical Modifier</p><h2>Boons</h2></div>{boonEligible && <strong>{summary.boonLoading ? '—' : summary.boonDashboard?.inventoryCount ?? 0} / 2<small> Owned</small></strong>}</header>
          {!boonEligible ? <div className="loadout-card-empty"><strong>Sign in to earn Boons</strong><p>Guest profiles can manage OCs, but persistent Boon Points and inventory require a player account.</p></div>
            : summary.boonLoading ? <p className="loadout-card-state">Loading your Boon inventory...</p>
              : summary.boonError ? <div className="loadout-card-state error" role="alert"><span>{summary.boonError}</span><button type="button" className="text-button" onClick={() => void summary.refresh()}>Try again</button></div>
                : equippedBoon ? <div className={`loadout-equipped-boon rarity-${equippedBoon.definition.rarity}`}>
                  <span className="loadout-boon-mark" aria-hidden="true">✦</span>
                  <div className="loadout-equipped-boon-copy">
                    <span className={`boon-rarity ${equippedBoon.definition.rarity}`}>{equippedBoon.definition.rarity}</span>
                    <h3>{equippedBoon.definition.name}</h3>
                    <span className="loadout-boon-equipped"><span aria-hidden="true">✓</span> Equipped</span>
                    <p>{equippedBoon.definition.description}</p>
                  </div>
                  <span className="loadout-boon-watermark" aria-hidden="true">✦</span>
                </div>
                  : <div className="loadout-card-empty"><strong>No Boon equipped</strong><p>Inventory {summary.boonDashboard?.inventoryCount ?? 0} / 2</p></div>}
          {matchBoon.loading && boonEligible ? <ActiveMatchBoonLoading /> : matchBoon.activeMatch && <ActiveMatchBoonNotice activeMatch={matchBoon.activeMatch} />}
          {matchBoon.error && <p className="loadout-match-boon-error" role="alert">{matchBoon.error}</p>}
          <p className="loadout-card-description">Choose one reusable tactical modifier for your ranked loadout.</p>
          {boonEligible ? <Link className="button button-primary" to="/boons">Manage</Link> : <span className="button button-secondary disabled" aria-disabled="true">Boons Require Sign-In</span>}
        </article>
      </div>}
    </section>
  </main>
}
