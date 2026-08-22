import { useSoundPreference } from './SoundContext'
export function SoundToggle(){const {enabled,toggle}=useSoundPreference();return <button type="button" className="sound-toggle" aria-label={`Sound effects ${enabled?'on':'off'}`} aria-pressed={enabled} title={`Sound Effects: ${enabled?'On':'Off'}`} onClick={toggle}><span aria-hidden="true">{enabled?'♪':'×'}</span></button>}
