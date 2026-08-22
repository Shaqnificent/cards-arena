import { AppHeader } from '../components/AppHeader'
import { LeaderboardEmptyState } from '../components/LeaderboardEmptyState'
import { LoadingScreen } from '../components/LoadingScreen'
import { PlayerAvatar } from '../components/PlayerAvatar'
import { useLeaderboard } from '../hooks/useLeaderboard'

interface LeaderboardProps {
  currentUserId: string
  username: string
  avatarUrl: string | null
}

export function Leaderboard({ currentUserId, username, avatarUrl }: LeaderboardProps) {
  const { players, loading, error } = useLeaderboard(100)

  if (loading) return <LoadingScreen message="Loading the arena rankings..." />

  return (
    <main className="catalogue-page">
      <AppHeader active="leaderboard" username={username} avatarUrl={avatarUrl} />

      <section className="catalogue-content leaderboard-content" aria-labelledby="leaderboard-heading">
        <p className="eyebrow">Hall of Champions</p>
        <h1 id="leaderboard-heading">Leaderboard</h1>
        <p className="catalogue-intro">Top 100 players who have won at least one match.</p>

        {error ? (
          <div className="catalogue-state error-message" role="alert">
            Unable to load the leaderboard. Please try again later.
          </div>
        ) : players.length === 0 ? (
          <LeaderboardEmptyState />
        ) : (
          <div className="leaderboard-table-wrap">
            <table className="leaderboard-table">
              <thead>
                <tr><th>Rank</th><th>Player</th><th>Wins</th><th>Losses</th><th>Games</th><th>Win Rate</th></tr>
              </thead>
              <tbody>
                {players.map((player) => {
                  const isCurrentPlayer = player.id === currentUserId
                  return (
                    <tr key={player.id} className={isCurrentPlayer ? 'current-player' : undefined}>
                      <td><span className={`rank rank-${player.rank}`}>#{player.rank}</span></td>
                      <td>
                        <div className="leaderboard-player">
                          <PlayerAvatar username={player.username} avatarUrl={player.avatarUrl} compact />
                          <span>{player.username}{isCurrentPlayer && <small>You</small>}</span>
                        </div>
                      </td>
                      <td>{player.wins}</td><td>{player.losses}</td><td>{player.gamesPlayed}</td>
                      <td className="win-rate">{player.winRate.toFixed(1)}%</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
  )
}
