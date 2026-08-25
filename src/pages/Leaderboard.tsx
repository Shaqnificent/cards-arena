import { useState } from 'react'
import { Link } from 'react-router-dom'
import { AppHeader } from '../components/AppHeader'
import { LeaderboardEmptyState } from '../components/LeaderboardEmptyState'
import { PlayerAvatar } from '../components/PlayerAvatar'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { useOcLeaderboard } from '../features/ocs/hooks/useOcLeaderboard'
import { usePlayerCharacters } from '../features/ocs/hooks/usePlayerCharacters'
import type { OcFamilyRank, OcIndividualRank, OcLeaderboardSort } from '../features/ocs/leaderboardTypes'
import { OCImage } from '../features/ocs/components/OCImage'
import { SystemBadge } from '../components/SystemBadge'

interface LeaderboardProps { currentUserId:string; username:string; avatarUrl:string|null }
type Section='players'|'ocs'; type OcSection='individual'|'family'

export function Leaderboard({currentUserId,username,avatarUrl}:LeaderboardProps){
  const [section,setSection]=useState<Section>('players');const [ocSection,setOcSection]=useState<OcSection>('individual');const [ocSort,setOcSort]=useState<OcLeaderboardSort>('overall')
  const playerData=useLeaderboard(100)
  const oc=useOcLeaderboard(ocSection,ocSort,section==='ocs')
  const own=usePlayerCharacters();const equipped=own.characters.filter(c=>c.active&&c.equipped).length
  const mode=section==='players'?'Players':ocSection==='individual'?labelSort(ocSort):`Family ${ocSort==='overall'?'OVR':labelSort(ocSort)}`
  const loadedCount=section==='players'?playerData.players.length:oc.rows.length
  return <main className="catalogue-page leaderboard-page"><AppHeader active="leaderboard" username={username} avatarUrl={avatarUrl}/><section className="catalogue-content leaderboard-content">
    <header className="leaderboard-hero"><div><p className="eyebrow">Hall of Champions</p><h1>Leaderboard</h1></div><LeaderboardSummary loadedCount={loadedCount} equipped={equipped} mode={mode}/></header>
    <div className="leaderboard-filter-stack">
      <div className="leaderboard-view-switch"><Segmented options={[['players','Players'],['ocs','OC Rankings']]} value={section} onChange={setSection}/></div>
      {section==='ocs'&&<div className="leaderboard-filter-panel">
        <SelectFilter label="Category" icon="person" options={[['individual','Individual'],['family','Family']]} value={ocSection} onChange={setOcSection}/>
        <SelectFilter label="Sort by" icon="target" options={[['overall','Overall'],['power','Battle Power'],['growth','Growth']]} value={ocSort} onChange={setOcSort}/>
        <button type="button" className="leaderboard-refresh" disabled={oc.loading} onClick={oc.refresh}><span aria-hidden="true">↻</span>{oc.loading?'Refreshing...':'Refresh'}</button>
      </div>}
    </div>
    {section==='players'?<PlayerRankings {...playerData} currentUserId={currentUserId}/>:<>
      {ocSection==='family'&&equipped<3&&<p className="family-eligibility"><strong>{equipped} / 3 OCs equipped</strong><span>Equip 3 active fighters to qualify for family rankings.</span></p>}
      {oc.loading?<RankingSkeleton/>:oc.error?<StateCard tone="error" title="Unable to load OC rankings" text="Please try again after confirming the OC leaderboard migration is installed."/>:oc.rows.length===0?<StateCard title={ocSection==='individual'?'No OCs ranked yet.':'No OC families ranked yet.'} text={ocSection==='individual'?'Create an active OC fighter to enter the rankings.':'Equip 3 active OCs to qualify for family rankings.'}/>:ocSection==='individual'?<IndividualRows rows={oc.rows as OcIndividualRank[]} currentUserId={currentUserId} sort={ocSort}/>:<FamilyRows rows={oc.rows as OcFamilyRank[]} currentUserId={currentUserId} sort={ocSort}/>} 
    </>}
  </section></main>
}

function LeaderboardSummary({loadedCount,equipped,mode}:{loadedCount:number;equipped:number;mode:string}){return <aside className="leaderboard-summary"><Summary icon="♛" label="Ranked results" value={loadedCount.toLocaleString()} note="Current top results"/><Summary icon="♙" label="Your OC family" value={`${equipped} / 3`} note="Active fighters equipped"/><Summary icon="⌖" label="Current mode" value={mode} note="Leaderboard ordering"/></aside>}
function Summary({icon,label,value,note}:{icon:string;label:string;value:string;note:string}){return <div className="summary-stat"><i>{icon}</i><span><small>{label}</small><strong>{value}</strong><em>{note}</em></span></div>}
function Segmented<T extends string>({options,value,onChange}:{options:[T,string][];value:T;onChange:(value:T)=>void}){return <div className="segmented-control" role="group" aria-label="Leaderboard filter">{options.map(([key,label])=><button key={key} type="button" aria-pressed={value===key} className={value===key?'active':''} onClick={()=>onChange(key)}>{label}</button>)}</div>}
function SelectFilter<T extends string>({label,icon,options,value,onChange}:{label:string;icon:'person'|'target';options:[T,string][];value:T;onChange:(value:T)=>void}){return <label className="leaderboard-select-filter"><span>{label}</span><div className="leaderboard-select-control"><FilterIcon type={icon}/><select value={value} onChange={(event)=>onChange(event.target.value as T)}>{options.map(([key,text])=><option key={key} value={key}>{text}</option>)}</select><i aria-hidden="true">⌄</i></div></label>}
function FilterIcon({type}:{type:'person'|'target'}){return type==='person'?<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.2"/><path d="M5.5 19c.5-4 2.7-6 6.5-6s6 2 6.5 6"/></svg>:<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2.5"/></svg>}

function PlayerRankings({players,loading,error,currentUserId}:{players:ReturnType<typeof useLeaderboard>['players'];loading:boolean;error:string|null;currentUserId:string}){
  if(loading)return <RankingSkeleton/>;if(error)return <StateCard tone="error" title="Unable to load the leaderboard" text="Please try again later."/>;if(!players.length)return <LeaderboardEmptyState/>
  return <div className="leaderboard-table-wrap"><table className="leaderboard-table"><thead><tr><th>Rank</th><th>Player</th><th>Wins</th><th>Losses</th><th>Games</th><th>Win Rate</th></tr></thead><tbody>{players.map(p=><tr key={p.id} className={p.id===currentUserId?'current-player':undefined}><td><RankBadge rank={p.rank}/></td><td>{p.isSystemPlayer?<div className="leaderboard-player"><PlayerAvatar username={p.username} avatarUrl={p.avatarUrl} compact/><span>{p.username}<SystemBadge visible/></span></div>:<Link className="leaderboard-player leaderboard-profile-link" to={`/profile/${p.id}`} aria-label={`View ${p.username}'s profile`}><PlayerAvatar username={p.username} avatarUrl={p.avatarUrl} compact/><span>{p.username}{p.id===currentUserId&&<small>You</small>}</span></Link>}</td><td>{p.wins}</td><td>{p.losses}</td><td>{p.gamesPlayed}</td><td className="win-rate">{p.winRate.toFixed(1)}%</td></tr>)}</tbody></table></div>
}
function RankBadge({rank}:{rank:number}){return <div className={`rank-medal rank-medal-${rank<=3?rank:'standard'}`}><span>{rank}</span>{rank<=3&&<i/>}</div>}
function OcAvatar({name,url}:{name:string;url:string|null}){return <OCImage src={url} name={name} className="oc-rank-avatar"/>}
function IndividualRows({rows,currentUserId,sort}:{rows:OcIndividualRank[];currentUserId:string;sort:OcLeaderboardSort}){return <div className="oc-rank-list">{rows.map(r=><article key={r.id} className={`oc-ranking-card rank-card-${r.rank<=3?r.rank:'standard'} ${r.ownerId===currentUserId?'current-player':''}`}><RankBadge rank={r.rank}/><OcAvatar name={r.name} url={r.imageUrl}/><div className="rank-identity"><h2>{r.name}{r.ownerId===currentUserId&&<small>You</small>}</h2><p>{r.verseName}</p><span>Owner: {r.ownerUsername}</span></div><strong className="rank-primary">{sort==='power'?<>{r.powerScore.toLocaleString()} <small>Power</small></>:sort==='growth'?<>+{r.growth} <small>OVR</small></>:<>{r.overall} <small>OVR</small></>}</strong><div className="rank-details"><span>◈ <b>{r.overall} / {r.overallCap}</b> OVR</span><span>ϟ <b>{r.powerScore.toLocaleString()} / {r.powerScoreCap.toLocaleString()}</b> Power</span><span>↗ Started {r.startingOverall} · <b className={r.growth>0?'positive':''}>+{r.growth}</b></span></div></article>)}</div>}
function FamilyRows({rows,currentUserId,sort}:{rows:OcFamilyRank[];currentUserId:string;sort:OcLeaderboardSort}){return <div className="oc-rank-list">{rows.map(r=><article key={r.ownerId} className={`oc-ranking-card family-card rank-card-${r.rank<=3?r.rank:'standard'} ${r.ownerId===currentUserId?'current-player':''}`}><RankBadge rank={r.rank}/><OcAvatar name={r.username} url={r.avatarUrl}/><div className="rank-identity"><h2>{r.username}{r.ownerId===currentUserId&&<small>You</small>}</h2><p>Active OC Family</p><span>3 fighters equipped</span></div><strong className="rank-primary">{sort==='power'?<>{Number(r.avgPowerScore).toLocaleString(undefined,{maximumFractionDigits:1})} <small>Avg Power</small></>:sort==='growth'?<>+{r.totalGrowth} <small>OVR</small></>:<>{Number(r.avgOverall).toFixed(1)} <small>Avg OVR</small></>}</strong><div className="rank-details family-preview"><span>Avg OVR <b>{Number(r.avgOverall).toFixed(1)}</b></span><span>Avg Power <b>{Number(r.avgPowerScore).toLocaleString(undefined,{maximumFractionDigits:1})}</b></span><span>Total Growth <b className="positive">+{r.totalGrowth}</b></span>{r.family.map(oc=><em key={oc.id}><b>{oc.name}</b>{sort==='growth'?`${oc.startingOverall} → ${oc.overall}`:`${oc.overall} OVR`}</em>)}</div></article>)}</div>}
function RankingSkeleton(){return <div className="ranking-skeleton" aria-label="Loading rankings">{[1,2,3].map(row=><div key={row}><i/><span/><b/><em/></div>)}</div>}
function StateCard({title,text,tone}:{title:string;text:string;tone?:'error'}){return <div className={`leaderboard-state-card ${tone??''}`}><h2>{title}</h2><p>{text}</p></div>}
function labelSort(sort:OcLeaderboardSort){return sort==='power'?'Power':sort[0].toUpperCase()+sort.slice(1)}
