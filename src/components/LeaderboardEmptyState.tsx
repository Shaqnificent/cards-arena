interface LeaderboardEmptyStateProps {
  compact?: boolean
}

export function LeaderboardEmptyState({ compact = false }: LeaderboardEmptyStateProps) {
  return (
    <div className={compact ? 'leaderboard-empty compact' : 'catalogue-state'}>
      <h2>No ranked players yet.</h2>
      <p>Players appear here after winning their first match.</p>
    </div>
  )
}
