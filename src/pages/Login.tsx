import { useState } from 'react'
import { supabase } from '../lib/supabase'

interface LoginProps {
  initialError?: string | null
}

export function Login({ initialError = null }: LoginProps) {
  const [error, setError] = useState<string | null>(initialError)
  const [pendingAction, setPendingAction] = useState<'google' | 'guest' | null>(null)

  const handleGoogleLogin = async () => {
    setError(null)
    setPendingAction('google')
    const redirectTo = new URL('/', window.location.origin).toString()

    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo },
    })

    if (authError) {
      setError(authError.message)
      setPendingAction(null)
    }
  }

  const handleGuestLogin = async () => {
    setError(null)
    setPendingAction('guest')

    const { error: authError } = await supabase.auth.signInAnonymously()

    if (authError) {
      setError(authError.message)
      setPendingAction(null)
    }
  }

  const isPending = pendingAction !== null

  return (
    <main className="login-page">
      <header className="login-header"><strong><i aria-hidden="true">⚔</i> ANIME <span>ARENA</span></strong><small><i aria-hidden="true">◇</i> Fair Play</small></header>
      <section className="login-content" aria-labelledby="login-title">
        <div className="login-intro"><p className="eyebrow">Build your team. Own the arena.</p><h1 id="login-title">ANIME <span>ARENA</span></h1><p>Strategize, battle, and rise through the ranks in fast-paced<br/>anime-inspired PvP battles.</p></div>
        <section className="login-panel">
          {error && <p className="error-message" role="alert">{error}</p>}
          <button className="button button-primary login-google" onClick={handleGoogleLogin} disabled={isPending}><i aria-hidden="true">G</i>{pendingAction === 'google' ? 'Connecting...' : 'Continue with Google'}</button>
          <div className="divider"><span>or</span></div>
          <button className="button button-secondary login-guest" onClick={handleGuestLogin} disabled={isPending}><i aria-hidden="true">♙</i>{pendingAction === 'guest' ? 'Entering Arena...' : 'Play as Guest'}</button>
          <p className="login-trust"><span aria-hidden="true">◇</span> Secure <i>•</i> Private <i>•</i> Respects Your Progress</p>
        </section>
        <div className="login-features"><article><i aria-hidden="true">⚔</i><span><strong>Draft Battles</strong><small>Build the perfect team</small></span></article><article><i aria-hidden="true">♟</i><span><strong>Build OCs</strong><small>Create and grow your roster</small></span></article><article><i aria-hidden="true">♛</i><span><strong>Ranked PvP</strong><small>Climb the leaderboards</small></span></article></div>
        <footer className="login-footer"><span>◇</span> Server-authoritative matchmaking <i>•</i> Skill-based progression</footer>
      </section>
    </main>
  )
}
