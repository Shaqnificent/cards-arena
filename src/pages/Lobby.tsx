import { useState } from 'react'
import { Link } from 'react-router-dom'
import type { User } from '@supabase/supabase-js'
import { AppHeader } from '../components/AppHeader'
import { LoadingScreen } from '../components/LoadingScreen'
import { LeaderboardPreview } from '../components/LeaderboardPreview'
import { PlayerAvatar } from '../components/PlayerAvatar'
import { MatchmakingControls } from '../components/MatchmakingControls'
import { cancelMatchmaking } from '../features/matchmaking/services/matchmaking'
import type { MatchmakingController, MatchmakingState } from '../features/matchmaking/types'
import { supabase } from '../lib/supabase'
import type { Profile } from '../types/profile'
import { useLoadoutSummary } from '../features/loadout/hooks/useLoadoutSummary'

interface LobbyProps { user: User; profile: Profile | null; profileLoading: boolean; profileError: string | null; matchmaking: MatchmakingController }

function getQueueCopy(status: MatchmakingState, administratorMatched: boolean) {
  if (status === 'searching' || status === 'joining' || status === 'cancelling') return { label: 'Searching', title: 'Finding an opponent...', description: 'Stay ready. The arena is searching for your match.' }
  if (status === 'matched') return administratorMatched
    ? { label: 'System Match', title: 'Administrator has entered the Arena', description: 'Entering your ranked system match now.' }
    : { label: 'Match Found', title: 'Opponent found!', description: 'Entering your shared match now.' }
  if (status === 'checking') return { label: 'Checking', title: 'Restoring your status...', description: 'Checking for an active match or queue entry.' }
  if (status === 'error') return { label: 'Offline', title: 'Matchmaking interrupted', description: 'Use Find Match to try connecting again.' }
  return { label: 'Online', title: 'Ready to fight!', description: 'Jump into the arena and test your skills.' }
}

export function Lobby({ user, profile, profileLoading, profileError, matchmaking }: LobbyProps) {
  const [signOutError, setSignOutError] = useState<string | null>(null)
  const loadout = useLoadoutSummary({
    enabled: Boolean(profile) && !profileLoading,
    boonEligible: Boolean(profile && !profile.is_guest && !profile.is_system_player),
    systemProfile: profile?.is_system_player ?? false,
  })

  const handleSignOut = async () => {
    setSignOutError(null)
    try { await cancelMatchmaking() } catch { /* Keep sign-out available if matchmaking is unavailable. */ }
    const { error } = await supabase.auth.signOut()
    if (error) setSignOutError(error.message)
  }

  if (profileLoading) return <LoadingScreen message="Loading your player profile..." />
  if (profileError || !profile) return <main className="screen"><section className="panel"><h1>ANIME ARENA</h1>
    <p className="error-message" role="alert">Unable to load your profile: {profileError ?? 'Profile not found.'}</p>
    <button className="button button-secondary" onClick={handleSignOut}>Sign Out</button></section></main>

  const gamesPlayed = profile.wins + profile.losses
  const winRate = gamesPlayed === 0 ? 0 : Math.round((profile.wins / gamesPlayed) * 100)
  const avatarUrl = profile.avatar_url ?? user.user_metadata.avatar_url ?? user.user_metadata.picture ?? null
  const queueCopy = getQueueCopy(matchmaking.status, matchmaking.administratorMatched)
  const equippedBoon = loadout.boonDashboard?.boons.find((boon) => boon.equipped) ?? null
  const displayedBoonPoints = loadout.boonDashboard?.boonPoints ?? profile.boon_points

  return <main className="lobby-page">
    <AppHeader active="play" username={profile.username} avatarUrl={avatarUrl} />

    <div className="lobby-dashboard">
      <section className="lobby-hero" aria-labelledby="lobby-title"><div className="lobby-energy" aria-hidden="true" /><div className="lobby-hero-content">
        <p className="eyebrow">Player Lobby</p><h1 id="lobby-title">ANIME ARENA</h1>
        <div className="lobby-player">
          <PlayerAvatar username={profile.username} avatarUrl={avatarUrl} />
          <div>
            <h2>{profile.username}</h2>
            <p className="record">{profile.wins} {profile.wins === 1 ? 'Win' : 'Wins'} <span>•</span> {profile.losses} {profile.losses === 1 ? 'Loss' : 'Losses'} <span>•</span> {winRate}% Win Rate</p>
            <Link className="boon-balance" to="/boons" aria-label={`${displayedBoonPoints.toLocaleString()} Boon Points. Manage Boons.`}><span aria-hidden="true">✦</span><b>{loadout.boonLoading ? '—' : displayedBoonPoints.toLocaleString()}</b><small>BP</small><em>Manage</em></Link>
          </div>
        </div>
        <Link className="ranked-loadout-summary" to="/loadout" aria-label="Review your ranked match loadout">
          <span className="ranked-loadout-heading"><small>Ranked Loadout</small><strong>Review before matchmaking</strong><i aria-hidden="true">&rsaquo;</i></span>
          <span><small>OC Family</small><strong>{!loadout.hasLoaded || loadout.ocLoading ? '—' : `${loadout.ocMembers.length} / 3`}</strong></span>
          <span><small>Boon</small><strong>{!loadout.hasLoaded || loadout.boonLoading ? '—' : equippedBoon?.definition.name ?? 'None Equipped'}</strong>{equippedBoon && <em>{equippedBoon.definition.rarity}</em>}</span>
        </Link>
        <MatchmakingControls {...matchmaking} />
      </div></section>

      <LeaderboardPreview />

      <section className="dashboard-card queue-card"><div className="dashboard-heading"><h2>Queue Status</h2><span className={matchmaking.status === 'searching' ? 'searching' : ''}>● {queueCopy.label}</span></div>
        <div className="queue-content"><div className="queue-radar"><i>?</i></div><div><strong>{queueCopy.title}</strong><p>{queueCopy.description}</p></div></div></section>

      <section className="dashboard-card stats-card"><div className="dashboard-heading"><h2>Game Stats</h2></div><div className="stats-grid">
        <div><span aria-hidden="true">⚔</span><strong>{profile.wins}</strong><small>Wins</small></div><div><span aria-hidden="true">◇</span><strong>{profile.losses}</strong><small>Losses</small></div><div><span aria-hidden="true">◎</span><strong>{winRate}%</strong><small>Win Rate</small></div>
      </div></section>

      <section className="dashboard-card features-card"><div className="dashboard-heading"><h2>Features</h2></div><ul>
        <li><span>♟</span><div><strong>Online Matchmaking</strong><p>Find opponents and battle in real time.</p></div></li>
        <li><span>★</span><div><strong>Playable Roster</strong><p>Browse the growing Anime Arena roster.</p></div></li>
        <li><span>ϟ</span><div><strong>Fast-Paced Battles</strong><p>Draft five fighters and battle first-to-three.</p></div></li>
      </ul></section>
    </div>

    <footer className="lobby-footer"><div><strong>“Skill. Strategy. Spirit.”</strong><p>Prove yourself in the Anime Arena.</p></div><button className="text-button" onClick={handleSignOut}>Sign Out <span aria-hidden="true">↪</span></button></footer>
    {signOutError && <p className="lobby-signout-error error-message" role="alert">{signOutError}</p>}
  </main>
}
