import { useEffect, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { PlayerAvatar } from './PlayerAvatar'

type ActivePage = 'play' | 'characters' | 'loadout' | 'leaderboard' | 'suggestions'

interface AppHeaderProps {
  active: ActivePage
  username: string
  avatarUrl: string | null
}

const navigation: Array<{ key: ActivePage; label: string; to: string }> = [
  { key: 'play', label: 'Play', to: '/' },
  { key: 'characters', label: 'Characters', to: '/characters' },
  { key: 'leaderboard', label: 'Leaderboard', to: '/leaderboard' },
  { key: 'loadout', label: 'Loadout', to: '/loadout' },
  { key: 'suggestions', label: 'Community', to: '/community' },
]

export function AppHeader({ active, username, avatarUrl }: AppHeaderProps) {
  const location = useLocation()
  const [mobileMenuPath, setMobileMenuPath] = useState<string | null>(null)
  const mobileMenuOpen = mobileMenuPath === location.pathname

  useEffect(() => {
    if (!mobileMenuOpen) return
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMobileMenuPath(null)
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [mobileMenuOpen])

  return <header className="app-header">
    <Link className="brand-link" to="/" onClick={() => setMobileMenuPath(null)}>ANIME ARENA</Link>
    <nav className="lobby-nav" aria-label="Primary navigation">
      {navigation.map((item) => <Link key={item.key} className={`nav-link${active === item.key ? ' active' : ''}`} aria-current={active === item.key ? 'page' : undefined} to={item.to}>{item.label}</Link>)}
    </nav>
    <PlayerAvatar compact username={username} avatarUrl={avatarUrl} />
    <button
      type="button"
      className={`mobile-nav-toggle${mobileMenuOpen ? ' open' : ''}`}
      aria-label={mobileMenuOpen ? 'Close navigation menu' : 'Open navigation menu'}
      aria-controls="mobile-primary-navigation"
      aria-expanded={mobileMenuOpen}
      onClick={() => setMobileMenuPath((path) => path === location.pathname ? null : location.pathname)}
    >
      <span /><span /><span />
    </button>
    {mobileMenuOpen && <nav id="mobile-primary-navigation" className="mobile-nav-panel" aria-label="Mobile primary navigation">
      <small>Menu</small>
      {navigation.map((item) => <Link key={item.key} className={active === item.key ? 'active' : undefined} aria-current={active === item.key ? 'page' : undefined} to={item.to} onClick={() => setMobileMenuPath(null)}>{item.label}</Link>)}
    </nav>}
  </header>
}
