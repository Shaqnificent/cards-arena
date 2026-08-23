import { Link } from 'react-router-dom'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { LeaderboardEmptyState } from './LeaderboardEmptyState'
import { PlayerAvatar } from './PlayerAvatar'

export function LeaderboardPreview() {
  const { players, loading, error } = useLeaderboard(5)

  return (
    <section className="leaderboard-preview" aria-labelledby="top-players-heading">
      <div className="preview-heading">
        <h2 id="top-players-heading">Top Players</h2>
        <span>Top 5</span>
      </div>

      {loading ? (
        <p className="preview-status" aria-live="polite">Loading rankings...</p>
      ) : error ? (
        <p className="preview-status preview-error" role="alert">Rankings are unavailable right now.</p>
      ) : players.length === 0 ? (
        <LeaderboardEmptyState compact />
      ) : (
        <ol className="preview-list">
          {players.map((player) => (
            <li key={player.id}>
              <span><strong className={player.rank === 1 ? 'preview-rank first' : 'preview-rank'}>{player.rank === 1 ? '♛' : player.rank}</strong><PlayerAvatar compact username={player.username} avatarUrl={player.avatarUrl} /><em>{player.username}</em></span>
              <b>{player.winRate.toFixed(1)}%</b>
            </li>
          ))}
        </ol>
      )}

      <Link className="preview-link" to="/leaderboard">View Full Leaderboard <span aria-hidden="true">→</span></Link>
    </section>
  )
}
