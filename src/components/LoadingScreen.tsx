interface LoadingScreenProps {
  message?: string
}

export function LoadingScreen({ message = 'Loading...' }: LoadingScreenProps) {
  return (
    <main className="screen" aria-live="polite" aria-busy="true">
      <div className="spinner" aria-hidden="true" />
      <p>{message}</p>
    </main>
  )
}
