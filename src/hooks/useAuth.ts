import { useEffect, useState } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

export interface AuthState {
  user: User | null
  session: Session | null
  loading: boolean
  error: string | null
}

export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>({
    user: null,
    session: null,
    loading: true,
    error: null,
  })

  useEffect(() => {
    let isMounted = true
    let authStateRevision = 0

    const loadSession = async () => {
      const revisionAtStart = authStateRevision
      const {
        data: { session },
        error,
      } = await supabase.auth.getSession()

      // Do not let a slower initialization response overwrite a newer auth event.
      if (isMounted && revisionAtStart === authStateRevision) {
        setState({
          user: session?.user ?? null,
          session,
          loading: false,
          error: error?.message ?? null,
        })
      }
    }

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        if (isMounted) {
          authStateRevision += 1
          setState({
            user: session?.user ?? null,
            session,
            loading: false,
            error: null,
          })
        }
      },
    )

    void loadSession()

    return () => {
      isMounted = false
      authListener.subscription.unsubscribe()
    }
  }, [])

  return state
}
