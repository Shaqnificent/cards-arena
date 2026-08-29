import type { GamePlayer } from '../types'

interface TeamPanelProps {
  player: GamePlayer
  label: string
  helperText?: string
}

export function TeamPanel({ player, label, helperText }: TeamPanelProps) {
  return (
    <aside className="team-panel">
      <div className="team-panel-heading"><span>{label}</span><b>${player.balance}</b></div>
      <p>{player.team.length} / 5 fighters</p>
      <ol>
        {player.team.map((character) => (
          <li key={character.id}><span>{character.name}</span><b>{character.overall}</b></li>
        ))}
        {Array.from({ length: 5 - player.team.length }, (_, index) => (
          <li className="empty-slot" key={index}><i aria-hidden="true">+</i><span>Empty slot</span></li>
        ))}
      </ol>
      {helperText && <div className="team-panel-helper"><i aria-hidden="true">i</i><span>{helperText}</span></div>}
    </aside>
  )
}
