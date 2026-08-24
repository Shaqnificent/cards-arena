import { useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabase'

interface BoonBalanceState {
  balance: number
  loading: boolean
}

export function useBoonBalance(initialBalance: number): BoonBalanceState {
  const [state, setState] = useState<BoonBalanceState>({ balance: initialBalance, loading: true })

  useEffect(() => {
    let current = true

    const load = async () => {
      const { data, error } = await supabase.rpc('get_my_boon_balance')
      if (!current) return
      if (error) {
        console.error('Boon Point balance load failed', {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        })
        setState({ balance: initialBalance, loading: false })
        return
      }
      setState({ balance: typeof data === 'number' ? data : Number(data ?? initialBalance), loading: false })
    }

    void load()
    return () => { current = false }
  }, [initialBalance])

  return state
}
