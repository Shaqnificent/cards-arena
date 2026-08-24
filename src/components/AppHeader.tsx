import { Link } from 'react-router-dom'
import { PlayerAvatar } from './PlayerAvatar'

type ActivePage = 'play' | 'characters' | 'loadout' | 'leaderboard' | 'suggestions'

interface AppHeaderProps {
  active: ActivePage
  username: string
  avatarUrl: string | null
}

export function AppHeader({ active, username, avatarUrl }: AppHeaderProps) {
  return <header className="app-header">
    <Link className="brand-link" to="/">ANIME ARENA</Link>
    <nav className="lobby-nav" aria-label="Primary navigation">
      {active === 'play' ? <span className="nav-link active" aria-current="page">Play</span> : <Link className="nav-link" to="/">Play</Link>}
      {active === 'characters' ? <span className="nav-link active" aria-current="page">Characters</span> : <Link className="nav-link" to="/characters">Characters</Link>}
      {active === 'leaderboard' ? <span className="nav-link active" aria-current="page">Leaderboard</span> : <Link className="nav-link" to="/leaderboard">Leaderboard</Link>}
      {active === 'loadout' ? <span className="nav-link active" aria-current="page">Loadout</span> : <Link className="nav-link" to="/loadout">Loadout</Link>}
      {active === 'suggestions' ? <span className="nav-link active" aria-current="page">Community</span> : <Link className="nav-link" to="/community">Community</Link>}
    </nav>
    <PlayerAvatar compact username={username} avatarUrl={avatarUrl} />
  </header>
}
