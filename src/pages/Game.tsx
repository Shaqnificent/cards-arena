import { Link } from 'react-router-dom'
import { LoadingScreen } from '../components/LoadingScreen'
import { BattleBoard } from '../features/game/components/BattleBoard'
import { DraftBoard } from '../features/game/components/DraftBoard'
import { MatchResult } from '../features/game/components/MatchResult'
import { useLocalGame } from '../features/game/hooks/useLocalGame'
import { useCharacters } from '../hooks/useCharacters'

interface GameProps { playerName: string }

export function Game({ playerName }: GameProps) {
  const { characters, loading, error } = useCharacters()

  if (loading) return <LoadingScreen message="Preparing the local arena..." />

  if (error) {
    return <main className="screen"><section className="panel"><h1>Game Unavailable</h1><p className="error-message">Unable to load playable characters.</p><Link className="button button-secondary" to="/">Return to Lobby</Link></section></main>
  }

  return <LoadedGame characters={characters} playerName={playerName} />
}

interface LoadedGameProps { characters: ReturnType<typeof useCharacters>['characters']; playerName: string }

function LoadedGame({ characters, playerName }: LoadedGameProps) {
  const { state, currentCharacter, actions } = useLocalGame(characters, playerName)

  if (state.error) {
    return <main className="screen"><section className="panel"><h1>Game Unavailable</h1><p className="error-message">{state.error}</p><Link className="button button-secondary" to="/">Return to Lobby</Link></section></main>
  }

  return (
    <main className="game-page">
      <header className="game-header"><Link className="brand-link" to="/">ANIME ARENA</Link><span>Local Prototype</span><Link className="nav-link" to="/">Exit Match</Link></header>
      {state.phase === 'draft' && currentCharacter && <DraftBoard state={state} currentCharacter={currentCharacter} actions={actions} />}
      {state.phase === 'battle' && <BattleBoard state={state} onSelect={actions.selectBattleCard} onLock={actions.lockBattleCard} onContinue={actions.continueBattle} />}
      {state.phase === 'result' && <MatchResult state={state} onRestart={actions.restart} />}
    </main>
  )
}
