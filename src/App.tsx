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

function App() {
  const { user, loading: authLoading, error: authError } = useAuth()
  const { profile, loading: profileLoading, error: profileError } = useProfile(user)

  if (authLoading) {
    return <LoadingScreen message="Checking your player session..." />
  }

  if (!user) {
    return <Login initialError={authError} />
  }

  const headerUsername = profile?.username ?? user.user_metadata.full_name ?? user.user_metadata.name ?? 'Player'
  const headerAvatarUrl = profile?.avatar_url ?? user.user_metadata.avatar_url ?? user.user_metadata.picture ?? null

  return (
    <Routes>
      <Route
        path="/"
        element={
          <Lobby
            user={user}
            profile={profile}
            profileLoading={profileLoading}
            profileError={profileError}
          />
        }
      />
      <Route path="/characters" element={<Characters username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/ocs" element={<PlayerCharacters username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/leaderboard" element={<Leaderboard currentUserId={user.id} username={headerUsername} avatarUrl={headerAvatarUrl} />} />
      <Route path="/suggestions" element={profile ? <Suggestions currentUserId={user.id} profile={profile} avatarUrl={headerAvatarUrl} /> : <LoadingScreen message="Loading your player profile..." />} />
      <Route path="/play/test" element={profile ? <Game playerName={profile.username} /> : <LoadingScreen message="Loading your player profile..." />} />
      <Route path="/match/:matchId" element={<Match currentUserId={user.id} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default App
