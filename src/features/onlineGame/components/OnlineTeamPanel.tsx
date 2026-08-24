import type { PublicGameProfile } from '../../../types/profile'
import type { OnlineMatchCharacter, OnlineMatchPlayer } from '../types'
import { SystemBadge } from '../../../components/SystemBadge'

interface OnlineTeamPanelProps {
  label: string
  profile: PublicGameProfile
  player: OnlineMatchPlayer
  team: OnlineMatchCharacter[]
}

export function OnlineTeamPanel({ label, profile, player, team }: OnlineTeamPanelProps) {
  return (
    <aside className="team-panel online-team-panel">
      <div className="team-panel-heading"><span>{label}</span><b>${player.balance}</b></div>
      <p>{profile.username} <SystemBadge visible={profile.is_system_player} /> · {team.length} / 5 fighters</p>
      <ol>
        {team.map((card) => (
          <li key={card.id}>
            <span>{card.character.name}<small>{card.purchase_price === 0 ? 'Free' : `$${card.purchase_price}`}</small></span>
            <b>{card.character.overall}</b>
          </li>
        ))}
        {Array.from({ length: 5 - team.length }, (_, index) => <li className="empty-slot" key={index}>Empty slot</li>)}
      </ol>
    </aside>
  )
}
