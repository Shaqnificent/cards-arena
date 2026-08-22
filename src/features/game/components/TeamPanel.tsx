import type { GamePlayer } from '../types'

interface TeamPanelProps {
  player: GamePlayer
  label: string
}

export function TeamPanel({ player, label }: TeamPanelProps) {
  return (
    <aside className="team-panel">
      <div className="team-panel-heading"><span>{label}</span><b>${player.balance}</b></div>
      <p>{player.team.length} / 5 fighters</p>
      <ol>
        {player.team.map((character) => (
          <li key={character.id}><span>{character.name}</span><b>{character.overall}</b></li>
        ))}
        {Array.from({ length: 5 - player.team.length }, (_, index) => <li className="empty-slot" key={index}>Empty slot</li>)}
      </ol>
    </aside>
  )
}
