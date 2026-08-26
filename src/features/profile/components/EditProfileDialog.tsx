import { useEffect, useMemo, useRef, useState } from 'react'
import { PlayerAvatar } from '../../../components/PlayerAvatar'
import type { AvatarMode } from '../../../types/profile'
import {
  avatarBackgrounds,
  avatarForegrounds,
  isAvatarColorPairValid,
  preferredForeground,
  USERNAME_PATTERN,
  type ProfileIdentityUpdate,
} from '../avatarIdentity'
import { checkUsernameAvailability, updateProfileIdentity, type UsernameAvailabilityStatus } from '../services/profileIdentity'

interface EditProfileDialogProps {
  username: string
  avatarUrl: string | null
  avatarMode: AvatarMode
  avatarBgColor: string
  avatarTextColor: string
  usernameChangesRemaining: number
  onClose: () => void
  onSaved: (identity: ProfileIdentityUpdate) => void
}

export function EditProfileDialog(props: EditProfileDialogProps) {
  const [username, setUsername] = useState(props.username)
  const [avatarMode, setAvatarMode] = useState(props.avatarMode)
  const [background, setBackground] = useState(props.avatarBgColor)
  const [foreground, setForeground] = useState(props.avatarTextColor)
  const [availabilityResult, setAvailabilityResult] = useState<{ username: string; status: UsernameAvailabilityStatus } | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const dialogRef = useRef<HTMLElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)
  const normalizedUsername = username.trim()
  const usernameChanged = normalizedUsername.toLowerCase() !== props.username.toLowerCase()
  const usernameValid = USERNAME_PATTERN.test(normalizedUsername)
  const colorsValid = isAvatarColorPairValid(background, foreground)
  const availability: UsernameAvailabilityStatus | 'checking' = !usernameChanged ? 'current'
    : !usernameValid ? 'invalid'
      : availabilityResult?.username.toLowerCase() === normalizedUsername.toLowerCase() ? availabilityResult.status : 'checking'
  const checking = availability === 'checking'
  const canSave = usernameValid && colorsValid && !checking && !saving &&
    (!usernameChanged || (props.usernameChangesRemaining > 0 && availability === 'available'))

  useEffect(() => {
    closeRef.current?.focus()
  }, [])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        props.onClose()
        return
      }
      if (event.key !== 'Tab' || !dialogRef.current) return
      const focusable = [...dialogRef.current.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), [tabindex]:not([tabindex="-1"])')]
      if (!focusable.length) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [props])

  useEffect(() => {
    if (!usernameChanged || !usernameValid || availabilityResult?.username.toLowerCase() === normalizedUsername.toLowerCase()) return
    let current = true
    const timer = window.setTimeout(() => {
      void checkUsernameAvailability(normalizedUsername)
        .then((result) => { if (current) setAvailabilityResult({ username: normalizedUsername, status: result.status }) })
        .catch(() => { if (current) setError('Could not check username availability. Try again.') })
    }, 400)
    return () => { current = false; window.clearTimeout(timer) }
  }, [availabilityResult?.username, normalizedUsername, usernameChanged, usernameValid])

  const availabilityCopy = useMemo(() => {
    if (!usernameChanged) return 'Current username'
    if (checking) return 'Checking availability...'
    if (availability === 'available') return 'Username is available'
    if (availability === 'taken') return 'That username is already taken'
    if (availability === 'reserved') return 'That username is reserved'
    return 'Use 3-20 letters, numbers, or underscores'
  }, [availability, checking, usernameChanged])
  const changeCountCopy = props.usernameChangesRemaining === 0 ? 'No username changes remaining'
    : props.usernameChangesRemaining === 1 ? 'Final username change remaining'
      : `${props.usernameChangesRemaining} of 3 username changes remaining`

  const save = async () => {
    if (!canSave) return
    setSaving(true)
    setError(null)
    try {
      const identity = await updateProfileIdentity({
        username: normalizedUsername,
        avatarMode,
        avatarBgColor: background,
        avatarTextColor: foreground,
      })
      props.onSaved(identity)
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : ''
      if (/already taken/i.test(message)) setAvailabilityResult({ username: normalizedUsername, status: 'taken' })
      setError(message || 'Could not update your profile. Try again.')
    } finally {
      setSaving(false)
    }
  }

  return <div className="profile-editor-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) props.onClose() }}>
    <section ref={dialogRef} className="profile-editor" role="dialog" aria-modal="true" aria-labelledby="profile-editor-title">
      <header>
        <div><p className="eyebrow">Player identity</p><h2 id="profile-editor-title">Edit Profile</h2></div>
        <button ref={closeRef} type="button" className="profile-editor-close" onClick={props.onClose} aria-label="Close profile editor">&times;</button>
      </header>

      <div className="profile-editor-preview">
        <PlayerAvatar username={normalizedUsername || props.username} avatarUrl={props.avatarUrl} avatarMode={avatarMode} avatarBgColor={background} avatarTextColor={foreground} />
        <div><small>Live preview</small><strong>{normalizedUsername || props.username}</strong></div>
      </div>

      <label className="profile-editor-username">
        <span>Username</span>
        <input value={username} maxLength={20} disabled={props.usernameChangesRemaining === 0} aria-describedby="username-status username-counter" onChange={(event) => { setUsername(event.target.value); setError(null) }} />
        <small id="username-status" role="status" aria-live="polite" className={`username-status status-${checking ? 'checking' : availability}`}>{availabilityCopy}</small>
        <small id="username-counter">{changeCountCopy}</small>
      </label>

      <fieldset className="profile-editor-modes">
        <legend>Avatar</legend>
        <label className={avatarMode === 'google' ? 'selected' : undefined}>
          <input type="radio" name="avatar-mode" value="google" checked={avatarMode === 'google'} disabled={!props.avatarUrl} onChange={() => setAvatarMode('google')} />
          <PlayerAvatar compact username={normalizedUsername || props.username} avatarUrl={props.avatarUrl} avatarMode="google" avatarBgColor={background} avatarTextColor={foreground} />
          <span><strong>Google photo</strong><small>{props.avatarUrl ? 'Use your current account photo' : 'No Google photo available'}</small></span>
        </label>
        <label className={avatarMode === 'initial' ? 'selected' : undefined}>
          <input type="radio" name="avatar-mode" value="initial" checked={avatarMode === 'initial'} onChange={() => setAvatarMode('initial')} />
          <PlayerAvatar compact username={normalizedUsername || props.username} avatarUrl={null} avatarMode="initial" avatarBgColor={background} avatarTextColor={foreground} />
          <span><strong>Initial avatar</strong><small>Choose your color pairing</small></span>
        </label>
      </fieldset>

      {avatarMode === 'initial' && <div className="profile-editor-palettes">
        <fieldset><legend>Background</legend><div>{avatarBackgrounds.map((color) => <button key={color.value} type="button" className={background === color.value ? 'selected' : undefined} style={{ backgroundColor: color.value }} aria-label={`${color.label} background`} aria-pressed={background === color.value} onClick={() => { setBackground(color.value); setForeground(preferredForeground(color.value)) }}><span aria-hidden="true">&#10003;</span></button>)}</div></fieldset>
        <fieldset><legend>Letter</legend><div>{avatarForegrounds.map((color) => { const disabled = !isAvatarColorPairValid(background, color.value); return <button key={color.value} type="button" disabled={disabled} className={foreground === color.value ? 'selected' : undefined} style={{ backgroundColor: color.value }} aria-label={`${color.label} letter color${disabled ? ', unavailable for selected background' : ''}`} aria-pressed={foreground === color.value} onClick={() => setForeground(color.value)}><span aria-hidden="true">A</span></button> })}</div></fieldset>
      </div>}

      {error && <p className="profile-editor-error" role="alert">{error}</p>}
      <footer><button type="button" className="button button-secondary" onClick={props.onClose}>Cancel</button><button type="button" className="button button-primary" disabled={!canSave} onClick={() => void save()}>{saving ? 'Saving...' : 'Save Profile'}</button></footer>
    </section>
  </div>
}
