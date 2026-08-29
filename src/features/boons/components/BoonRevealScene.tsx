import { Float, RoundedBox, Sparkles } from '@react-three/drei'
import { Canvas, useFrame } from '@react-three/fiber'
import { useRef } from 'react'
import type { Group } from 'three'
import type { BoonRarity } from '../types'

interface BoonRevealSceneProps {
  rarity: BoonRarity | null
  revealed: boolean
}

const rarityEffects: Record<BoonRarity, { color: string; secondary: string; intensity: number; particles: number }> = {
  common: { color: '#cbd5e1', secondary: '#64748b', intensity: .7, particles: 24 },
  rare: { color: '#60a5fa', secondary: '#2563eb', intensity: .9, particles: 32 },
  epic: { color: '#c084fc', secondary: '#7c3aed', intensity: 1.08, particles: 40 },
  legendary: { color: '#fbbf24', secondary: '#d97706', intensity: 1.3, particles: 52 },
  mythic: { color: '#f472d0', secondary: '#c026d3', intensity: 1.5, particles: 64 },
}

function FloatingCard({ color, secondary, intensity, revealed }: { color: string; secondary: string; intensity: number; revealed: boolean }) {
  const card = useRef<Group>(null)
  useFrame(({ clock }, delta) => {
    if (!card.current) return
    card.current.rotation.y += Math.min(delta, .05) * (revealed ? .34 : .18)
    card.current.rotation.x = Math.sin(clock.getElapsedTime() * .7) * .045
  })
  return <Float speed={revealed ? 1.7 : 1.1} rotationIntensity={.12} floatIntensity={.32}>
    <group ref={card}>
      <RoundedBox args={[2.18,3.08,.14]} radius={.13} smoothness={4}>
        <meshStandardMaterial color="#090712" metalness={.62} roughness={.28} emissive={secondary} emissiveIntensity={revealed ? .14 * intensity : .035} />
      </RoundedBox>
      <RoundedBox args={[1.96,2.86,.025]} radius={.1} smoothness={3} position={[0,0,.085]}>
        <meshStandardMaterial color="#130d22" metalness={.25} roughness={.4} emissive={secondary} emissiveIntensity={revealed ? .2 * intensity : .05} />
      </RoundedBox>
      <mesh position={[0,0,.115]} rotation={[0,0,Math.PI / 4]}>
        <octahedronGeometry args={[.48,0]} />
        <meshStandardMaterial color={color} emissive={color} emissiveIntensity={revealed ? intensity : .22} metalness={.6} roughness={.2} />
      </mesh>
      <mesh position={[0,0,.135]}><torusGeometry args={[.76,.025,8,64]} /><meshBasicMaterial color={color} toneMapped={false} /></mesh>
    </group>
  </Float>
}

function AuraRing({ color, intensity, revealed }: { color: string; intensity: number; revealed: boolean }) {
  const ring = useRef<Group>(null)
  useFrame((_, delta) => {
    if (!ring.current) return
    ring.current.rotation.z += Math.min(delta, .05) * (revealed ? .34 : .16)
    ring.current.rotation.y -= Math.min(delta, .05) * .08
  })
  return <group ref={ring} position={[0,0,-.45]}>
    <mesh><torusGeometry args={[1.72,.025 * intensity,8,96]} /><meshBasicMaterial color={color} transparent opacity={revealed ? .72 : .3} toneMapped={false} /></mesh>
    <mesh rotation={[0,0,Math.PI / 6]}><torusGeometry args={[2.02,.012 * intensity,6,96]} /><meshBasicMaterial color={color} transparent opacity={revealed ? .38 : .15} toneMapped={false} /></mesh>
    {Array.from({ length: 12 }, (_, index) => {
      const angle = index / 12 * Math.PI * 2
      return <mesh key={index} position={[Math.cos(angle) * 1.86,Math.sin(angle) * 1.86,0]} rotation={[0,0,angle]}><boxGeometry args={[.08,.24,.018]} /><meshBasicMaterial color={color} transparent opacity={revealed ? .78 : .28} toneMapped={false} /></mesh>
    })}
  </group>
}

function Particles({ color, intensity, count }: { color: string; intensity: number; count: number }) {
  return <Sparkles count={count} scale={[5.4,5.4,2.2]} size={1.7 * intensity} speed={.22} noise={.45} color={color} opacity={Math.min(.9,.38 * intensity)} />
}

function Scene({ rarity, revealed }: BoonRevealSceneProps) {
  const effect = rarityEffects[rarity ?? 'epic']
  return <><ambientLight intensity={.55} /><pointLight position={[3,3,4]} color={effect.color} intensity={(revealed ? 14 : 5) * effect.intensity} distance={9} /><pointLight position={[-3,-2,2]} color={effect.secondary} intensity={(revealed ? 8 : 3) * effect.intensity} distance={8} /><AuraRing color={effect.color} intensity={effect.intensity} revealed={revealed} /><Particles color={effect.color} intensity={effect.intensity} count={effect.particles} /><FloatingCard color={effect.color} secondary={effect.secondary} intensity={effect.intensity} revealed={revealed} /></>
}

export default function BoonRevealScene(props: BoonRevealSceneProps) {
  return <Canvas camera={{ position: [0,0,6.3], fov: 42 }} dpr={[1,1.5]} gl={{ alpha: true, antialias: true, powerPreference: 'high-performance' }} onCreated={({ gl }) => gl.setClearColor(0x000000,0)}><Scene {...props} /></Canvas>
}
