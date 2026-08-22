import { useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabase'
import type { OcFamilyRank, OcIndividualRank, OcLeaderboardSort } from '../leaderboardTypes'

export function useOcLeaderboard(kind:'individual'|'family', sort:OcLeaderboardSort, enabled:boolean) {
  const [rows,setRows]=useState<(OcIndividualRank|OcFamilyRank)[]>([])
  const [loadedKey,setLoadedKey]=useState<string|null>(null)
  const [loading,setLoading]=useState(false)
  const [error,setError]=useState<string|null>(null)
  const requestKey=`${kind}:${sort}`
  useEffect(()=>{
    if(!enabled)return
    let current=true
    const load=async()=>{setLoading(true);setError(null)
      const fn=kind==='individual'?'get_oc_individual_leaderboard':'get_oc_family_leaderboard'
      const {data,error:requestError}=await supabase.rpc(fn,{p_sort:sort,p_limit:100,p_offset:0})
      if(!current)return
      if(requestError){setRows([]);setError(requestError.message)}else setRows((data??[]) as (OcIndividualRank|OcFamilyRank)[])
      setLoadedKey(requestKey)
      setLoading(false)
    }
    void load();return()=>{current=false}
  },[enabled,kind,requestKey,sort])
  const queryChanged=enabled&&loadedKey!==requestKey
  return {rows:queryChanged?[]:rows,loading:loading||queryChanged,error:queryChanged?null:error}
}
