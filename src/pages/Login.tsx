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

    const { error: authError } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
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
    <main className="screen">
      <section className="panel login-panel" aria-labelledby="login-title">
        <p className="eyebrow">Build your team. Own the arena.</p>
        <h1 id="login-title">ANIME ARENA</h1>

        {error && <p className="error-message" role="alert">{error}</p>}

        <button className="button button-primary" onClick={handleGoogleLogin} disabled={isPending}>
          {pendingAction === 'google' ? 'Connecting...' : 'Continue with Google'}
        </button>
        <div className="divider"><span>or</span></div>
        <button className="button button-secondary" onClick={handleGuestLogin} disabled={isPending}>
          {pendingAction === 'guest' ? 'Entering Arena...' : 'Play as Guest'}
        </button>
      </section>
    </main>
  )
}
