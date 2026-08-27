import { lazy, Suspense, type ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { LoadingScreen } from './components/LoadingScreen'
import { useAuth } from './hooks/useAuth'
import { useProfile } from './hooks/useProfile'
import { Lobby } from './pages/Lobby'
import { Login } from './pages/Login'
import { SoundProvider } from './features/audio/SoundProvider'
import { MatchmakingToast } from './components/MatchmakingToast'
import { useMatchmaking } from './features/matchmaking/hooks/useMatchmaking'
import type { User } from '@supabase/supabase-js'
import type { Profile } from './types/profile'
import { PlayerChallengeProvider } from './features/challenges/PlayerChallengeProvider'
import { ChallengeToast } from './features/challenges/ChallengeToast'
import { supabaseConfigurationError } from './lib/supabase'

const Characters = lazy(() => import('./pages/Characters').then((module) => ({ default: module.Characters })))
const Leaderboard = lazy(() => import('./pages/Leaderboard').then((module) => ({ default: module.Leaderboard })))
const Game = lazy(() => import('./pages/Game').then((module) => ({ default: module.Game })))
const Match = lazy(() => import('./pages/Match').then((module) => ({ default: module.Match })))
const Suggestions = lazy(() => import('./pages/Suggestions').then((module) => ({ default: module.Suggestions })))
const PlayerCharacters = lazy(() => import('./pages/PlayerCharacters').then((module) => ({ default: module.PlayerCharacters })))
const PublicPlayerProfile = lazy(() => import('./pages/PublicPlayerProfile').then((module) => ({ default: module.PublicPlayerProfile })))
const Boons = lazy(() => import('./pages/Boons').then((module) => ({ default: module.Boons })))
const Loadout = lazy(() => import('./pages/Loadout').then((module) => ({ default: module.Loadout })))

function App() {
  if (supabaseConfigurationError) {
    return <ConfigurationError message={supabaseConfigurationError} />
  }

  return <ConfiguredApp />
}

function ConfiguredApp() {
  const { user, loading: authLoading, error: authError } = useAuth()
  const { profile, loading: profileLoading, error: profileError, refresh: refreshProfile, applyIdentity } = useProfile(user)

  if (authLoading) {
    return <LoadingScreen message="Checking your player session..." />
  }

  if (!user) {
    return <Login initialError={authError} />
  }

  return <AuthenticatedApp user={user} profile={profile} profileLoading={profileLoading} profileError={profileError} refreshProfile={refreshProfile} applyIdentity={applyIdentity} />
}

function AuthenticatedApp({ user, profile, profileLoading, profileError, refreshProfile, applyIdentity }: {
  user: User
  profile: Profile | null
  profileLoading: boolean
  profileError: string | null
  refreshProfile: () => Promise<void>
  applyIdentity: ReturnType<typeof useProfile>['applyIdentity']
}) {
  const matchmaking = useMatchmaking(user.id)

  const headerUsername = profile?.username ?? user.user_metadata.full_name ?? user.user_metadata.name ?? 'Player'
  const headerAvatarUrl = profile?.avatar_url ?? user.user_metadata.avatar_url ?? user.user_metadata.picture ?? null
  const headerIdentity = {
    profileId: profile && !profile.is_guest && !profile.is_system_player ? user.id : undefined,
    avatarMode: profile?.avatar_mode ?? (headerAvatarUrl ? 'google' as const : 'initial' as const),
    avatarBgColor: profile?.avatar_bg_color ?? '#7C3AED',
    avatarTextColor: profile?.avatar_text_color ?? '#FFFFFF',
  }

  const challengeEligible = Boolean(profile && !profile.is_guest && !profile.is_system_player)

  const withProfile = (content: ReactNode, message: string) => <ProfileBoundary profile={profile} loading={profileLoading} error={profileError} retry={refreshProfile} message={message}>{content}</ProfileBoundary>

  return <SoundProvider><PlayerChallengeProvider userId={user.id} eligible={challengeEligible}><Suspense fallback={<LoadingScreen message="Loading Anime Arena..." />}>
    <Routes>
      <Route
        path="/"
        element={
          <Lobby
            user={user}
            profile={profile}
            profileLoading={profileLoading}
            profileError={profileError}
            matchmaking={matchmaking}
          />
        }
      />
      <Route path="/characters" element={<Characters username={headerUsername} avatarUrl={headerAvatarUrl} {...headerIdentity} />} />
      <Route path="/loadout" element={withProfile(profile && <Loadout profile={profile} avatarUrl={headerAvatarUrl} />, 'Loading your Loadout...')} />
      <Route path="/ocs" element={withProfile(profile && <PlayerCharacters currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} isGuest={profile.is_guest} isSystemPlayer={profile.is_system_player} {...headerIdentity} />, 'Loading your OC Family...')} />
      <Route path="/boons" element={withProfile(profile && <Boons profile={profile} avatarUrl={headerAvatarUrl} />, 'Loading your Boon loadout...')} />
      <Route path="/leaderboard" element={<Leaderboard currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} {...headerIdentity} />} />
      <Route path="/profile/:playerId" element={<PublicPlayerProfile currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} onIdentitySaved={applyIdentity} {...headerIdentity} />} />
      <Route path="/community" element={withProfile(profile && <Suggestions currentUserId={user.id} profile={profile} avatarUrl={headerAvatarUrl} />, 'Loading your player profile...')} />
      <Route path="/suggestions" element={<Navigate to="/community" replace />} />
      <Route path="/play/test" element={withProfile(profile && <Game playerName={profile.username} />, 'Loading your player profile...')} />
      <Route path="/match/:matchId" element={<Match currentUserId={user.id} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    <MatchmakingToast matchmaking={matchmaking} />
    <ChallengeToast />
  </Suspense></PlayerChallengeProvider></SoundProvider>
}

function ProfileBoundary({ profile, loading, error, retry, message, children }: {
  profile: Profile | null
  loading: boolean
  error: string | null
  retry: () => Promise<void>
  message: string
  children: ReactNode
}) {
  if (loading) return <LoadingScreen message={message} />
  if (error || !profile) return <main className="screen"><section className="panel"><h1>Profile unavailable</h1><p className="error-message" role="alert">{error ?? 'Your player profile could not be loaded.'}</p><button type="button" className="button button-secondary" onClick={() => void retry()}>Retry</button></section></main>
  return children
}

function ConfigurationError({ message }: { message: string }) {
  return <main className="screen"><section className="panel"><h1>Configuration required</h1><p className="error-message" role="alert">{message}</p></section></main>
}

export default App
