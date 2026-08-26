import { useEffect, useRef, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { PlayerAvatar } from './PlayerAvatar'
import { cancelMatchmaking } from '../features/matchmaking/services/matchmaking'
import { supabase } from '../lib/supabase'
import type { AvatarMode } from '../types/profile'

type ActivePage = 'play' | 'characters' | 'loadout' | 'leaderboard' | 'suggestions'

interface AppHeaderProps {
  active: ActivePage
  username: string
  avatarUrl: string | null
  avatarMode?: AvatarMode
  avatarBgColor?: string
  avatarTextColor?: string
  profileId?: string
}

const navigation: Array<{ key: ActivePage; label: string; to: string }> = [
  { key: 'play', label: 'Play', to: '/' },
  { key: 'characters', label: 'Characters', to: '/characters' },
  { key: 'leaderboard', label: 'Leaderboard', to: '/leaderboard' },
  { key: 'loadout', label: 'Loadout', to: '/loadout' },
  { key: 'suggestions', label: 'Community', to: '/community' },
]

export function AppHeader({ active, username, avatarUrl, avatarMode, avatarBgColor, avatarTextColor, profileId }: AppHeaderProps) {
  const location = useLocation()
  const [mobileMenuPath, setMobileMenuPath] = useState<string | null>(null)
  const [profileMenuPath, setProfileMenuPath] = useState<string | null>(null)
  const [signingOut, setSigningOut] = useState(false)
  const [signOutError, setSignOutError] = useState<string | null>(null)
  const profileMenuRef = useRef<HTMLDivElement>(null)
  const mobileMenuOpen = mobileMenuPath === location.pathname
  const profileMenuOpen = profileMenuPath === location.pathname

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setMobileMenuPath(null)
        setProfileMenuPath(null)
      }
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [])

  useEffect(() => {
    if (!profileMenuOpen) return
    const closeOutside = (event: PointerEvent) => {
      if (!profileMenuRef.current?.contains(event.target as Node)) setProfileMenuPath(null)
    }
    document.addEventListener('pointerdown', closeOutside)
    return () => document.removeEventListener('pointerdown', closeOutside)
  }, [profileMenuOpen])

  const handleSignOut = async () => {
    if (signingOut) return
    setSigningOut(true)
    setSignOutError(null)
    try {
      try { await cancelMatchmaking() } catch { /* Sign-out remains available if matchmaking is unavailable. */ }
      const { error } = await supabase.auth.signOut()
      if (error) {
        setSignOutError(error.message)
        setSigningOut(false)
      }
    } catch (error) {
      setSignOutError(error instanceof Error ? error.message : 'Could not sign out. Try again.')
      setSigningOut(false)
    }
  }

  return <header className="app-header">
    <Link className="brand-link" to="/" onClick={() => setMobileMenuPath(null)}>ANIME ARENA</Link>
    <nav className="lobby-nav" aria-label="Primary navigation">
      {navigation.map((item) => <Link key={item.key} className={`nav-link${active === item.key ? ' active' : ''}`} aria-current={active === item.key ? 'page' : undefined} to={item.to}>{item.label}</Link>)}
    </nav>
    <div className="header-profile-menu" ref={profileMenuRef}>
      <button
        type="button"
        className={`header-profile-trigger${profileMenuOpen ? ' open' : ''}`}
        aria-label={`${username} profile menu`}
        aria-haspopup="menu"
        aria-expanded={profileMenuOpen}
        onClick={() => {
          setMobileMenuPath(null)
          setSignOutError(null)
          setProfileMenuPath((path) => path === location.pathname ? null : location.pathname)
        }}
      >
        <PlayerAvatar compact username={username} avatarUrl={avatarUrl} avatarMode={avatarMode} avatarBgColor={avatarBgColor} avatarTextColor={avatarTextColor} />
        <span className="header-profile-chevron" aria-hidden="true" />
      </button>
      {profileMenuOpen && <div className="header-profile-popover" role="menu">
        {profileId && <Link role="menuitem" to={`/profile/${profileId}`} onClick={() => setProfileMenuPath(null)}>
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="8" r="3.2"/><path d="M5.5 19c.5-4 2.7-6 6.5-6s6 2 6.5 6"/></svg>
          <span>View profile</span>
        </Link>}
        <button type="button" role="menuitem" disabled={signingOut} onClick={() => void handleSignOut()}>
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><path d="M10 5H6.8A1.8 1.8 0 0 0 5 6.8v10.4A1.8 1.8 0 0 0 6.8 19H10M14.5 8.5 18 12l-3.5 3.5M9 12h9" /></svg>
          <span>{signingOut ? 'Signing out…' : 'Sign out'}</span>
        </button>
        {signOutError && <p role="alert">{signOutError}</p>}
      </div>}
    </div>
    <button
      type="button"
      className={`mobile-nav-toggle${mobileMenuOpen ? ' open' : ''}`}
      aria-label={mobileMenuOpen ? 'Close navigation menu' : 'Open navigation menu'}
      aria-controls="mobile-primary-navigation"
      aria-expanded={mobileMenuOpen}
      onClick={() => {
        setProfileMenuPath(null)
        setMobileMenuPath((path) => path === location.pathname ? null : location.pathname)
      }}
    >
      <span /><span /><span />
    </button>
    {mobileMenuOpen && <nav id="mobile-primary-navigation" className="mobile-nav-panel" aria-label="Mobile primary navigation">
      <small>Menu</small>
      {navigation.map((item) => <Link key={item.key} className={active === item.key ? 'active' : undefined} aria-current={active === item.key ? 'page' : undefined} to={item.to} onClick={() => setMobileMenuPath(null)}>{item.label}</Link>)}
    </nav>}
  </header>
}
