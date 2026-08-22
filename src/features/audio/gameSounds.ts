export const SFX_STORAGE_KEY = 'anime-arena-sfx-enabled'
export const GAME_SOUNDS = {
  cardHover: { src: '/sounds/card-hover.mp3', volume: 0.15 },
  cardSelect: { src: '/sounds/card-select.mp3', volume: 0.25 },
  lockIn: { src: '/sounds/lock-in.mp3', volume: 0.25 },
  roundReveal: { src: '/sounds/round-reveal.mp3', volume: 0.15 },
  roundWin: { src: '/sounds/round-win.mp3', volume: 0.2 },
  roundLose: { src: '/sounds/round-lose.mp3', volume: 0.2 },
  roundDraw: { src: '/sounds/round-draw.mp3', volume: 0.2 },
  nextRound: { src: '/sounds/next-round.mp3', volume: 0.2 },
} as const
