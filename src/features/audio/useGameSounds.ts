import { useCallback, useMemo, useRef } from 'react'
import useSound from 'use-sound'
import { GAME_SOUNDS } from './gameSounds'
import { useSoundPreference } from './SoundContext'

export function useGameSounds() {
  const { enabled } = useSoundPreference()
  const [hover] = useSound(GAME_SOUNDS.cardHover.src, { volume: GAME_SOUNDS.cardHover.volume })
  const [select] = useSound(GAME_SOUNDS.cardSelect.src, { volume: GAME_SOUNDS.cardSelect.volume })
  const [lock] = useSound(GAME_SOUNDS.lockIn.src, { volume: GAME_SOUNDS.lockIn.volume })
  const [reveal] = useSound(GAME_SOUNDS.roundReveal.src, { volume: GAME_SOUNDS.roundReveal.volume })
  const [win] = useSound(GAME_SOUNDS.roundWin.src, { volume: GAME_SOUNDS.roundWin.volume })
  const [lose] = useSound(GAME_SOUNDS.roundLose.src, { volume: GAME_SOUNDS.roundLose.volume })
  const [draw] = useSound(GAME_SOUNDS.roundDraw.src, { volume: GAME_SOUNDS.roundDraw.volume })
  const [next] = useSound(GAME_SOUNDS.nextRound.src, { volume: GAME_SOUNDS.nextRound.volume })
  const lastHover = useRef(0)
  const guarded = useCallback((play: () => void) => { if (enabled) play() }, [enabled])
  return useMemo(() => ({
    playCardHover: () => { if (!window.matchMedia('(hover: hover) and (pointer: fine)').matches) return; const now=Date.now(); if(now-lastHover.current<75)return; lastHover.current=now; guarded(hover) },
    playCardSelect: () => guarded(select), playLockIn: () => guarded(lock), playRoundReveal: () => guarded(reveal),
    playRoundWin: () => guarded(win), playRoundLose: () => guarded(lose), playRoundDraw: () => guarded(draw), playNextRound: () => guarded(next),
  }), [draw, guarded, hover, lock, lose, next, reveal, select, win])
}
