import './App.css'
import { Navigate, Route, Routes } from 'react-router-dom'
import { LoadingScreen } from './components/LoadingScreen'
import { useAuth } from './hooks/useAuth'
import { useProfile } from './hooks/useProfile'
import { Lobby } from './pages/Lobby'
import { Login } from './pages/Login'
import { Characters } from './pages/Characters'
import { Leaderboard } from './pages/Leaderboard'
import { Game } from './pages/Game'
import { Match } from './pages/Match'
import { Suggestions } from './pages/Suggestions'
import { PlayerCharacters } from './pages/PlayerCharacters'
import { PublicPlayerProfile } from './pages/PublicPlayerProfile'
import { Boons } from './pages/Boons'
import { SoundProvider } from './features/audio/SoundProvider'
import { MatchmakingToast } from './components/MatchmakingToast'
import { useMatchmaking } from './features/matchmaking/hooks/useMatchmaking'
import type { User } from '@supabase/supabase-js'
import type { Profile } from './types/profile'

function App() {
  const { user, loading: authLoading, error: authError } = useAuth()
  const { profile, loading: profileLoading, error: profileError } = useProfile(user)

  if (authLoading) {
    return <LoadingScreen message="Checking your player session..." />
  }

  if (!user) {
    return <Login initialError={authError} />
  }

  return <AuthenticatedApp user={user} profile={profile} profileLoading={profileLoading} profileError={profileError} />
}

function AuthenticatedApp({ user, profile, profileLoading, profileError }: {
  user: User
  profile: Profile | null
  profileLoading: boolean
  profileError: string | null
}) {
  const matchmaking = useMatchmaking(user.id)

  const headerUsername = profile?.username ?? user.user_metadata.full_name ?? user.user_metadata.name ?? 'Player'
  const headerAvatarUrl = profile?.avatar_url ?? user.user_metadata.avatar_url ?? user.user_metadata.picture ?? null

  return <SoundProvider>
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
      <Route path="/characters" element={<Characters username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/ocs" element={<PlayerCharacters currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} isGuest={profile?.is_guest ?? true} isSystemPlayer={profile?.is_system_player ?? false} />} />
      <Route path="/boons" element={profile ? <Boons profile={profile} avatarUrl={headerAvatarUrl} /> : <LoadingScreen message="Loading your Boon loadout..." />} />
      <Route path="/leaderboard" element={<Leaderboard currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/profile/:playerId" element={<PublicPlayerProfile currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/community" element={profile ? <Suggestions currentUserId={user.id} profile={profile} avatarUrl={headerAvatarUrl} /> : <LoadingScreen message="Loading your player profile..." />} />
      <Route path="/suggestions" element={<Navigate to="/community" replace />} />
      <Route path="/play/test" element={profile ? <Game playerName={profile.username} /> : <LoadingScreen message="Loading your player profile..." />} />
      <Route path="/match/:matchId" element={<Match currentUserId={user.id} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    <MatchmakingToast matchmaking={matchmaking} />
  </SoundProvider>
}

export default App
