interface SystemBadgeProps {
  visible?: boolean
}

export function SystemBadge({ visible = true }: SystemBadgeProps) {
  return visible ? <small className="system-player-badge">System</small> : null
}
