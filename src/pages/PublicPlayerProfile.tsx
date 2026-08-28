import { useRef, useState, type CSSProperties } from 'react'
import { Link, useParams } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { PlayerAvatar } from '../components/PlayerAvatar'
import { OCImage } from '../features/ocs/components/OCImage'
import { usePublicPlayerProfile } from '../features/social/hooks/usePublicPlayerProfile'
import type { PublicOcFamilyMember } from '../features/social/types'
import { FamilyLogo } from '../features/social/components/FamilyLogo'
import { EditProfileDialog } from '../features/profile/components/EditProfileDialog'
import type { AvatarMode } from '../types/profile'
import type { ProfileIdentityUpdate } from '../features/profile/avatarIdentity'
import { ChallengeButton } from '../features/challenges/ChallengeButton'

interface PublicPlayerProfileProps {
  currentUserId: string
  username: string
  avatarUrl: string | null
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
  profileId?: string
  onIdentitySaved: (identity: ProfileIdentityUpdate) => void
}

export function PublicPlayerProfile({ currentUserId, username, avatarUrl, avatarMode, avatarBgColor, avatarTextColor, profileId, onIdentitySaved }: PublicPlayerProfileProps) {
  const { playerId } = useParams<{ playerId: string }>()
  const { profile, loading, unavailable, refresh } = usePublicPlayerProfile(playerId)
  const [loreMember, setLoreMember] = useState<PublicOcFamilyMember | null>(null)
  const [descriptionExpanded, setDescriptionExpanded] = useState(false)
  const [editorOpen, setEditorOpen] = useState(false)
  const editButtonRef = useRef<HTMLButtonElement>(null)
  const familyName = profile?.ocFamily.name ?? (profile ? `${profile.displayName}'s OC Family` : 'OC Family')
  const familyMembers = profile?.ocFamily.members ?? []

  return <main className="catalogue-page public-profile-page">
    <AppHeader active="leaderboard" username={username} avatarUrl={avatarUrl} avatarMode={avatarMode} avatarBgColor={avatarBgColor} avatarTextColor={avatarTextColor} profileId={profileId} />
    <section className="public-profile-content">
      <Link className="public-profile-back" to="/leaderboard">&larr; Back to leaderboard</Link>
      {loading ? <PublicProfileLoading /> : unavailable || !profile ? <PublicProfileUnavailable /> : <>
        <header className="public-profile-hero">
          <div className="public-profile-identity">
            <PlayerAvatar username={profile.displayName} avatarUrl={profile.avatarUrl} avatarMode={profile.avatarMode} avatarBgColor={profile.avatarBgColor} avatarTextColor={profile.avatarTextColor} />
            <div>
              <p className="eyebrow">Player profile</p>
              <h1>{profile.displayName}</h1>
              <div className="public-profile-meta">
                {profile.playerId === currentUserId && <span className="public-profile-you">Your profile</span>}
                <span>Joined {formatJoinedDate(profile.joinedAt)}</span>
              </div>
              <div className="public-profile-actions">
                {profile.playerId === currentUserId && <button ref={editButtonRef} type="button" className="public-profile-edit" onClick={() => setEditorOpen(true)}><span aria-hidden="true">&#9998;</span>Edit Profile</button>}
                {profile.playerId !== currentUserId && <ChallengeButton currentUserId={currentUserId} player={{id:profile.playerId,username:profile.displayName,avatarUrl:profile.avatarUrl,avatarMode:profile.avatarMode,avatarBgColor:profile.avatarBgColor,avatarTextColor:profile.avatarTextColor}}/>}
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
          <div className="public-family-brand">
            <FamilyLogo logoPath={profile.ocFamily.logoPath} updatedAt={profile.ocFamily.updatedAt} name={familyName} className="public-family-logo" />
            <div>
              <p className="eyebrow">Active OC Family</p>
              <h2>{familyName}</h2>
              {profile.ocFamily.tagline && <p className="public-family-tagline">{profile.ocFamily.tagline}</p>}
            </div>
            <strong>{familyMembers.length} / 3 Equipped</strong>
          </div>
          {profile.ocFamily.description && <div className="public-family-description"><p className={descriptionExpanded ? 'expanded' : undefined}>{profile.ocFamily.description}</p>{profile.ocFamily.description.length > 240 && <button type="button" onClick={() => setDescriptionExpanded((value) => !value)} aria-expanded={descriptionExpanded}>{descriptionExpanded ? 'Show less' : 'Read more'}</button>}</div>}
          {familyMembers.length === 0
            ? <div className="public-family-empty"><span aria-hidden="true">&#9823;</span><h3>No public OC Family equipped yet.</h3><p>This player&apos;s active fighters will appear here once equipped.</p></div>
            : <div className="public-family-grid" style={{ '--profile-card-accent': profile.avatarBgColor, '--profile-card-contrast': profile.avatarTextColor } as CSSProperties}>{familyMembers.map((member) => <PublicFamilyCard key={member.characterId} member={member} onReadLore={setLoreMember} />)}</div>}
        </section>
      </>}
    </section>
    {editorOpen && profile && profile.playerId === currentUserId && <EditProfileDialog
      username={profile.displayName}
      avatarUrl={profile.avatarUrl}
      avatarMode={profile.avatarMode}
      avatarBgColor={profile.avatarBgColor}
      avatarTextColor={profile.avatarTextColor}
      usernameChangesRemaining={profile.usernameChangesRemaining ?? 0}
      onClose={() => { setEditorOpen(false); window.requestAnimationFrame(() => editButtonRef.current?.focus()) }}
      onSaved={(identity) => {
        onIdentitySaved(identity)
        setEditorOpen(false)
        refresh()
        window.requestAnimationFrame(() => editButtonRef.current?.focus())
      }}
    />}
    {loreMember?.lore && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal public-lore-modal" role="dialog" aria-modal="true" aria-labelledby="public-lore-heading"><div className="oc-modal-heading"><div><p className="eyebrow">OC Background</p><h2 id="public-lore-heading">{loreMember.name}</h2><p>{loreMember.ocType === 'champion' ? 'Champion' : 'Sacrificial'} · {loreMember.verseName}</p></div><button onClick={() => setLoreMember(null)} aria-label="Close OC background">&times;</button></div><div className="public-lore-summary"><OCImage src={loreMember.imageUrl} name={loreMember.name} /><div><strong>{loreMember.overall} OVR</strong><span>{loreMember.powerScore.toLocaleString()} Battle Power</span></div></div><div className="public-lore-copy"><span>Background</span><p>{loreMember.lore}</p></div><button className="button button-primary" onClick={() => setLoreMember(null)}>Close</button></section></div>}
  </main>
}

function ProfileStat({ label, value }: { label: string; value: string }) {
  return <div><strong>{value}</strong><span>{label}</span></div>
}

function PublicFamilyCard({ member, onReadLore }: { member: PublicOcFamilyMember; onReadLore: (member: PublicOcFamilyMember) => void }) {
  return <article className="public-family-card">
    <div className="public-family-media">
      <OCImage src={member.imageUrl} name={member.name} />
      <span className="public-family-slot">Slot {member.slot}</span>
      <strong className="public-family-overall"><i aria-hidden="true" />{member.overall}<small>OVR</small></strong>
    </div>
    <div className="public-family-card-body">
      <div className="public-family-card-heading">
        <small>{member.verseName}</small>
        <h3>{member.name}</h3>
        <span className={`public-oc-type ${member.ocType}`}><i aria-hidden="true">{member.ocType === 'champion' ? '♛' : '◆'}</i>{member.ocType}</span>
      </div>
      {member.lore && <div className="public-family-lore"><p>{member.lore}</p><button type="button" onClick={() => onReadLore(member)}>Read full background <span aria-hidden="true">›</span></button></div>}
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
