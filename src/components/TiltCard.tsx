import { useEffect, useRef, type CSSProperties, type PointerEvent, type ReactNode } from 'react'

interface TiltCardProps { children: ReactNode; className?: string; style?: CSSProperties }
interface PointerPosition { x: number; y: number }

const MAX_ROTATE_X = 4
const MAX_ROTATE_Y = 5
const clamp = (value: number) => Math.min(1, Math.max(0, value))

export function TiltCard({ children, className = '', style }: TiltCardProps) {
  const cardRef = useRef<HTMLElement>(null)
  const frameRef = useRef<number | null>(null)
  const pointerRef = useRef<PointerPosition>({ x: .5, y: .5 })
  const disabledInteractionQueryRef = useRef<MediaQueryList | null>(null)

  useEffect(() => () => {
    if (frameRef.current !== null) window.cancelAnimationFrame(frameRef.current)
  }, [])

  const updateTilt = () => {
    frameRef.current = null
    const card = cardRef.current
    if (!card) return
    const { x, y } = pointerRef.current
    card.style.setProperty('--card-tilt-x', `${(.5 - y) * MAX_ROTATE_X * 2}deg`)
    card.style.setProperty('--card-tilt-y', `${(x - .5) * MAX_ROTATE_Y * 2}deg`)
    card.style.setProperty('--card-pointer-x', `${x * 100}%`)
    card.style.setProperty('--card-pointer-y', `${y * 100}%`)
    card.style.setProperty('--card-tilt-scale', '1.015')
    card.style.setProperty('--card-tilt-duration', '60ms')
  }

  const handlePointerMove = (event: PointerEvent<HTMLElement>) => {
    disabledInteractionQueryRef.current ??= window.matchMedia('(prefers-reduced-motion: reduce), (pointer: coarse), (hover: none)')
    if (event.pointerType !== 'mouse' || disabledInteractionQueryRef.current.matches) return
    const bounds = event.currentTarget.getBoundingClientRect()
    pointerRef.current = { x: clamp((event.clientX - bounds.left) / bounds.width), y: clamp((event.clientY - bounds.top) / bounds.height) }
    if (frameRef.current === null) frameRef.current = window.requestAnimationFrame(updateTilt)
  }

  const handlePointerLeave = (event: PointerEvent<HTMLElement>) => {
    if (event.pointerType !== 'mouse') return
    if (frameRef.current !== null) {
      window.cancelAnimationFrame(frameRef.current)
      frameRef.current = null
    }
    const card = event.currentTarget
    pointerRef.current = { x: .5, y: .5 }
    card.style.setProperty('--card-tilt-x', '0deg')
    card.style.setProperty('--card-tilt-y', '0deg')
    card.style.setProperty('--card-pointer-x', '50%')
    card.style.setProperty('--card-pointer-y', '50%')
    card.style.setProperty('--card-tilt-scale', '1')
    card.style.setProperty('--card-tilt-duration', '220ms')
  }

  return <article ref={cardRef} className={className} style={style} onPointerMove={handlePointerMove} onPointerLeave={handlePointerLeave} onPointerCancel={handlePointerLeave}>{children}</article>
}
