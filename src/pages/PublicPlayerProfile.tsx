import { Link, useParams } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { PlayerAvatar } from '../components/PlayerAvatar'
import { OCImage } from '../features/ocs/components/OCImage'
import { usePublicPlayerProfile } from '../features/social/hooks/usePublicPlayerProfile'
import type { PublicOcFamilyMember } from '../features/social/types'

interface PublicPlayerProfileProps {
  currentUserId: string
  username: string
  avatarUrl: string | null
}

export function PublicPlayerProfile({ currentUserId, username, avatarUrl }: PublicPlayerProfileProps) {
  const { playerId } = useParams<{ playerId: string }>()
  const { profile, loading, unavailable } = usePublicPlayerProfile(playerId)

  return <main className="catalogue-page public-profile-page">
    <AppHeader active="leaderboard" username={username} avatarUrl={avatarUrl} />
    <section className="public-profile-content">
      <Link className="public-profile-back" to="/leaderboard">&larr; Back to leaderboard</Link>
      {loading ? <PublicProfileLoading /> : unavailable || !profile ? <PublicProfileUnavailable /> : <>
        <header className="public-profile-hero">
          <div className="public-profile-identity">
            <PlayerAvatar username={profile.displayName} avatarUrl={profile.avatarUrl} />
            <div>
              <p className="eyebrow">Player profile</p>
              <h1>{profile.displayName}</h1>
              <div className="public-profile-meta">
                {profile.playerId === currentUserId && <span className="public-profile-you">Your profile</span>}
                <span>Joined {formatJoinedDate(profile.joinedAt)}</span>
              </div>
            </div>
          </div>
          <div className="public-profile-record" aria-label="Competitive record">
            <ProfileStat label="Wins" value={profile.wins.toLocaleString()} />
            <ProfileStat label="Losses" value={profile.losses.toLocaleString()} />
            <ProfileStat label="Win rate" value={`${profile.winRate.toFixed(1)}%`} />
            <ProfileStat label="Player rank" value={profile.rank === null ? 'Unranked' : `#${profile.rank}`} />
          </div>
        </header>

        <section className="public-family-section">
          <div className="public-family-heading">
            <div>
              <p className="eyebrow">Active OC Family</p>
              <h2>{profile.displayName}&apos;s Fighters</h2>
              <p>Currently equipped fighters from this player&apos;s active loadout.</p>
            </div>
            <strong>{profile.ocFamily.length} / 3 Equipped</strong>
          </div>
          {profile.ocFamily.length === 0
            ? <div className="public-family-empty"><span aria-hidden="true">&#9823;</span><h3>No public OC Family equipped yet.</h3><p>This player&apos;s active fighters will appear here once equipped.</p></div>
            : <div className="public-family-grid">{profile.ocFamily.map((member) => <PublicFamilyCard key={member.characterId} member={member} />)}</div>}
        </section>
      </>}
    </section>
  </main>
}

function ProfileStat({ label, value }: { label: string; value: string }) {
  return <div><strong>{value}</strong><span>{label}</span></div>
}

function PublicFamilyCard({ member }: { member: PublicOcFamilyMember }) {
  return <article className="public-family-card">
    <div className="public-family-media">
      <OCImage src={member.imageUrl} name={member.name} />
      <span>Slot {member.slot}</span>
      <strong>{member.overall}<small>OVR</small></strong>
    </div>
    <div className="public-family-card-body">
      <div className="public-family-card-heading">
        <div><small>{member.verseName}</small><h3>{member.name}</h3></div>
        <span className={`public-oc-type ${member.ocType}`}>{member.ocType}</span>
      </div>
      <dl>
        <div><dt>Overall</dt><dd>{member.overall} / {member.overallCap}</dd></div>
        <div><dt>Battle Power</dt><dd>{member.powerScore.toLocaleString()} / {member.powerScoreCap.toLocaleString()}</dd></div>
        <div><dt>Starting OVR</dt><dd>{member.startingOverall}</dd></div>
        <div><dt>Growth</dt><dd className={member.growth > 0 ? 'positive' : undefined}>+{member.growth}</dd></div>
      </dl>
    </div>
  </article>
}

function PublicProfileLoading() {
  return <div className="public-profile-state" aria-live="polite"><div className="spinner" /><h1>Loading player profile...</h1></div>
}

function PublicProfileUnavailable() {
  return <div className="public-profile-state"><span aria-hidden="true">?</span><h1>Profile unavailable</h1><p>This player profile does not exist or is not available publicly.</p><Link className="button button-primary" to="/leaderboard">Return to leaderboard</Link></div>
}

function formatJoinedDate(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'recently'
  return new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' }).format(date)
}
