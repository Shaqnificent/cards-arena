import type { AvatarMode } from '../../types/profile'

export const USERNAME_PATTERN = /^[A-Za-z0-9_]{3,20}$/

export const avatarBackgrounds = [
  { label: 'Obsidian', value: '#151126' },
  { label: 'Crimson', value: '#C92A5B' },
  { label: 'Violet', value: '#7C3AED' },
  { label: 'Magenta', value: '#D61F7C' },
  { label: 'Azure', value: '#2563EB' },
  { label: 'Cyan', value: '#0891B2' },
  { label: 'Emerald', value: '#059669' },
  { label: 'Gold', value: '#B7791F' },
  { label: 'Silver', value: '#6B7280' },
] as const

export const avatarForegrounds = [
  { label: 'White', value: '#FFFFFF' },
  { label: 'Gold', value: '#FBBF24' },
  { label: 'Lavender', value: '#C4B5FD' },
  { label: 'Pink', value: '#F9A8D4' },
  { label: 'Ink', value: '#11111A' },
] as const

const validPairs = new Set([
  '#151126:#FFFFFF', '#151126:#FBBF24', '#151126:#C4B5FD', '#151126:#F9A8D4',
  '#C92A5B:#FFFFFF', '#7C3AED:#FFFFFF', '#D61F7C:#FFFFFF', '#2563EB:#FFFFFF',
  '#0891B2:#11111A', '#059669:#11111A', '#B7791F:#11111A', '#6B7280:#FFFFFF',
])

export const isAvatarColorPairValid = (background: string, foreground: string) =>
  validPairs.has(`${background.toUpperCase()}:${foreground.toUpperCase()}`)

export const preferredForeground = (background: string) =>
  ['#0891B2', '#059669', '#B7791F'].includes(background.toUpperCase()) ? '#11111A' : '#FFFFFF'

export interface ProfileIdentityUpdate {
  username: string
  usernameChangesRemaining: number
  avatarMode: AvatarMode
  avatarUrl: string | null
  avatarBgColor: string
  avatarTextColor: string
}
