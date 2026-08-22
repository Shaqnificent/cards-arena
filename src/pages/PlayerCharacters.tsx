import { useMemo, useState } from 'react'
import { AppHeader } from '../components/AppHeader'
import { usePlayerCharacters } from '../features/ocs/hooks/usePlayerCharacters'
import { getGrowthType, type PlayerCharacter } from '../features/ocs/types'
import { getOverallUpgradeCost } from '../features/ocs/types'
import { useOcProgression } from '../features/ocs/hooks/useOcProgression'
import { useVerses } from '../hooks/useVerses'
import { OCImage } from '../features/ocs/components/OCImage'
import { removeOcPortrait, uploadOcPortrait, validatePortrait } from '../features/ocs/services/ocImages'

interface PlayerCharactersProps { username: string; avatarUrl: string | null }

const formatPower = (value: number) => value.toLocaleString()

function CharacterIdentity({ character }: { character: PlayerCharacter }) {
  return <div className="oc-identity">
    <OCImage src={character.image_url} name={character.name} className="oc-avatar" />
    <div><span>{character.verse.name}</span><h3>{character.name}</h3></div>
  </div>
}

export function PlayerCharacters({ username, avatarUrl }: PlayerCharactersProps) {
  const collection = usePlayerCharacters()
  const progression = useOcProgression()
  const { verses, loading: versesLoading, error: versesError } = useVerses()
  const [formOpen, setFormOpen] = useState(false)
  const [showRetired, setShowRetired] = useState(false)
  const [name, setName] = useState('')
  const [verseId, setVerseId] = useState('')
  const [actionError, setActionError] = useState<string | null>(null)
  const [created, setCreated] = useState<PlayerCharacter | null>(null)
  const [retiring, setRetiring] = useState<PlayerCharacter | null>(null)
  const [developing, setDeveloping] = useState<PlayerCharacter | null>(null)
  const [developmentMessage, setDevelopmentMessage] = useState<string | null>(null)
  const [rewardTargets, setRewardTargets] = useState<Record<string, string>>({})
  const [portraitCharacter, setPortraitCharacter] = useState<PlayerCharacter | null>(null)
  const [portraitFile, setPortraitFile] = useState<File | null>(null)
  const [portraitPreview, setPortraitPreview] = useState<string | null>(null)
  const [portraitPending, setPortraitPending] = useState(false)

  const active = useMemo(() => collection.characters.filter((character) => character.active), [collection.characters])
  const retired = useMemo(() => collection.characters.filter((character) => !character.active), [collection.characters])
  const equipped = active.filter((character) => character.equipped)
  const selectedVerseId = String(verseId || verses[0]?.id || '')

  const openCreation = () => {
    setActionError(null); setCreated(null); setName(''); setVerseId(verses[0]?.id ?? ''); setFormOpen(true)
  }

  const submitCreation = async () => {
    const normalizedName = name.trim()
    if (normalizedName.length < 2 || normalizedName.length > 50) return setActionError('OC name must be between 2 and 50 characters.')
    const verse = verses.find((option) => String(option.id) === selectedVerseId)
    if (!verse) return setActionError('Select an active verse.')
    setActionError(null)
    try { setCreated(await collection.create({ name: normalizedName, verse })) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to create your fighter.') }
  }

  const toggleEquipped = async (character: PlayerCharacter) => {
    setActionError(null)
    try { await collection.setEquipped(character) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to update your OC Family.') }
  }

  const confirmRetirement = async () => {
    if (!retiring) return
    setActionError(null)
    try { await collection.retire(retiring); setRetiring(null) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to retire this fighter.'); setRetiring(null) }
  }

  const claimReward = async (rewardId: string) => {
    const characterId = rewardTargets[rewardId] || active[0]?.id
    if (!characterId) return setActionError('Create an active OC before assigning progression.')
    setActionError(null)
    try { await progression.claim(rewardId, characterId); await collection.refresh() }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to assign this progression reward.') }
  }

  const develop = async (stat: 'overall' | 'power') => {
    if (!developing) return
    setActionError(null); setDevelopmentMessage(null)
    try {
      const updated = await progression.upgrade(developing, stat)
      setDeveloping({ ...updated, verse: developing.verse })
      setDevelopmentMessage(stat === 'overall' ? 'OVR increased by 1.' : `Battle Power increased to ${formatPower(updated.power_score)}.`)
      await collection.refresh()
    } catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to develop this fighter.') }
  }

  const choosePortrait = (file: File | null) => {
    if (portraitPreview) URL.revokeObjectURL(portraitPreview)
    setPortraitFile(null); setPortraitPreview(null); setActionError(null)
    if (!file) return
    const validation = validatePortrait(file)
    if (validation) return setActionError(validation)
    setPortraitFile(file); setPortraitPreview(URL.createObjectURL(file))
  }

  const savePortrait = async () => {
    if (!portraitCharacter || !portraitFile || portraitPending) return
    setPortraitPending(true); setActionError(null)
    try { await uploadOcPortrait(portraitCharacter.id, portraitFile, portraitCharacter.image_url); await collection.refresh(); setPortraitCharacter(null); choosePortrait(null) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to upload this portrait.') }
    finally { setPortraitPending(false) }
  }

  const removePortrait = async (character: PlayerCharacter) => {
    if (!character.image_url || portraitPending) return
    setPortraitPending(true); setActionError(null)
    try { await removeOcPortrait(character.id, character.image_url); await collection.refresh(); setPortraitCharacter(null); choosePortrait(null) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to remove this portrait.') }
    finally { setPortraitPending(false) }
  }

  return <main className="oc-page">
    <AppHeader active="ocs" username={username} avatarUrl={avatarUrl} />
    <section className="oc-content" aria-labelledby="oc-heading">
      <header className="oc-hero"><div><p className="eyebrow">My Fighters</p><h1 id="oc-heading">OC Family</h1><p>Create and develop your own fighters across the Anime Arena universes.</p></div><div className="oc-hero-actions"><strong>{equipped.length} / 3 <small>Equipped</small></strong><button className="button button-primary" onClick={openCreation} disabled={versesLoading || Boolean(versesError)}>+ Create OC</button></div></header>

      {actionError && <p className="oc-message error-message" role="alert">{actionError}</p>}
      {progression.error && <p className="oc-message error-message" role="alert">{progression.error}</p>}
      {(collection.error || versesError) && <div className="catalogue-state oc-state" role="alert"><h2>Unable to load OC data</h2><p>{collection.error ?? 'Unable to load active verses.'}</p><button className="button button-secondary" onClick={() => void collection.refresh()}>Retry</button></div>}

      {!collection.error && !versesError && <>
        {!progression.loading && progression.rewards.length > 0 && <section className="oc-rewards" aria-labelledby="rewards-heading"><div><p className="eyebrow">Unclaimed Progression</p><h2 id="rewards-heading">You have {progression.rewards.length} {progression.rewards.length === 1 ? 'reward' : 'rewards'} waiting</h2></div><div className="oc-reward-list">{progression.rewards.map((reward) => <article key={reward.id}><div><strong>Local Match Win</strong><span>+{reward.points} points</span></div><select aria-label="Assign reward to OC" value={rewardTargets[reward.id] || active[0]?.id || ''} disabled={active.length === 0} onChange={(event) => setRewardTargets((current) => ({ ...current, [reward.id]: event.target.value }))}><option value="" disabled>Choose a fighter</option>{active.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}</select><button className="button button-primary" disabled={active.length === 0 || progression.pendingKey === `claim:${reward.id}`} onClick={() => void claimReward(reward.id)}>Assign to OC</button></article>)}</div></section>}
        <section className="oc-section" aria-labelledby="family-heading"><div className="oc-section-heading"><div><p className="eyebrow">Active OC Family</p><h2 id="family-heading">Match Loadout</h2></div><span>Up to three fighters</span></div>
          <div className="oc-family-grid">{Array.from({ length: 3 }, (_, index) => {
            const character = equipped[index]
            return character ? <article className="oc-family-slot filled" key={character.id}><span className="oc-slot-label">Slot {index + 1}</span><OCImage src={character.image_url} name={character.name} className="oc-family-portrait" /><CharacterIdentity character={character} /><div className="oc-slot-stats"><b>{character.overall} <small>OVR</small></b><b>{formatPower(character.power_score)} <small>Power</small></b></div><div className="oc-portrait-actions"><button className="button button-secondary" onClick={() => { setPortraitCharacter(character); setPortraitFile(null); setPortraitPreview(null); setActionError(null) }}>{character.image_url ? 'Change Portrait' : 'Add Portrait'}</button>{character.image_url && <button className="text-button" disabled={portraitPending} onClick={() => void removePortrait(character)}>Remove</button>}</div></article>
              : <div className="oc-family-slot empty" key={`empty-${index}`}><span>+</span><strong>Empty Slot</strong><small>Equip an OC from your collection</small></div>
          })}</div>
        </section>

        <section className="oc-section" aria-labelledby="collection-heading"><div className="oc-section-heading"><div><p className="eyebrow">Your Fighters</p><h2 id="collection-heading">OC Collection</h2></div></div>
          {collection.loading ? <div className="catalogue-state oc-state"><h2>Loading your OC family...</h2></div>
            : active.length === 0 ? <div className="catalogue-state oc-state"><h2>No OC fighters yet.</h2><p>Create your first fighter and discover their potential.</p><button className="button button-primary" onClick={openCreation}>Create Your First OC</button></div>
            : <div className="oc-collection-grid">{active.map((character) => <article className={`oc-card${character.equipped ? ' equipped' : ''}`} key={character.id}><CharacterIdentity character={character} /><span className="oc-growth">{getGrowthType(character.starting_overall)}</span><div className="oc-stat-grid"><div><span>Current OVR</span><strong>{character.overall} <small>/ {character.overall_cap}</small></strong></div><div><span>Battle Power</span><strong>{formatPower(character.power_score)} <small>/ {formatPower(character.power_score_cap)}</small></strong></div><div><span>Starting OVR</span><strong>{character.starting_overall}</strong></div><div><span>Progression Points</span><strong>{character.progression_points}</strong></div></div><div className="oc-card-actions"><button className="button oc-develop-button" onClick={() => { setDeveloping(character); setDevelopmentMessage(null); setActionError(null) }}>Develop</button><button className="button button-primary" disabled={collection.pendingId === character.id} onClick={() => void toggleEquipped(character)}>{character.equipped ? 'Unequip' : 'Equip'}</button><button className="button oc-retire-button" disabled={collection.pendingId === character.id} onClick={() => setRetiring(character)}>Retire</button></div></article>)}</div>}
        </section>

        {retired.length > 0 && <section className="oc-retired"><button className="text-button" onClick={() => setShowRetired((value) => !value)} aria-expanded={showRetired}>Retired OCs ({retired.length}) <span>{showRetired ? '−' : '+'}</span></button>{showRetired && <div className="oc-retired-list">{retired.map((character) => <article key={character.id}><CharacterIdentity character={character} /><span>{character.overall} OVR</span><span>{formatPower(character.power_score)} Power</span><time dateTime={character.retired_at ?? ''}>Retired {character.retired_at ? new Date(character.retired_at).toLocaleDateString() : '—'}</time></article>)}</div>}</section>}
      </>}
    </section>

    {formOpen && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal" role="dialog" aria-modal="true" aria-labelledby="create-oc-heading">{created ? <div className="oc-reveal"><p className="eyebrow">Character Created</p><CharacterIdentity character={created} /><p>Your potential has been determined</p><div className="oc-reveal-stats"><div><span>Starting OVR</span><strong>{created.starting_overall}</strong></div><div><span>Growth Type</span><strong>{getGrowthType(created.starting_overall)}</strong></div><div><span>OVR Cap</span><strong>{created.overall_cap}</strong></div><div><span>Battle Power</span><strong>{formatPower(created.power_score)}</strong></div><div><span>Power Cap</span><strong>{formatPower(created.power_score_cap)}</strong></div></div><button className="button button-primary" onClick={() => setFormOpen(false)}>View My Fighter</button></div>
        : <><div className="oc-modal-heading"><div><p className="eyebrow">New Fighter</p><h2 id="create-oc-heading">Create OC</h2></div><button onClick={() => setFormOpen(false)} aria-label="Close creation form">×</button></div><label>OC Name<input maxLength={50} value={name} onChange={(event) => setName(event.target.value)} placeholder="Enter fighter name" /></label><label>Verse<select value={selectedVerseId} onChange={(event) => setVerseId(event.target.value)}><option value="" disabled>Select a verse</option>{verses.map((verse) => <option key={verse.id} value={verse.id}>{verse.name}</option>)}</select></label>{actionError && <p className="error-message" role="alert">{actionError}</p>}<div className="oc-modal-actions"><button className="button button-secondary" onClick={() => setFormOpen(false)}>Cancel</button><button className="button button-primary" disabled={collection.pendingId === 'create'} onClick={() => void submitCreation()}>{collection.pendingId === 'create' ? 'Evaluating Potential...' : 'Create Fighter'}</button></div></>}</section></div>}

    {retiring && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal compact" role="alertdialog" aria-modal="true" aria-labelledby="retire-oc-heading"><p className="eyebrow">Retire Fighter</p><h2 id="retire-oc-heading">Retire {retiring.name}?</h2><p>This fighter will leave your active collection and cannot be used in new matches.</p><div className="oc-modal-actions"><button className="button button-secondary" onClick={() => setRetiring(null)}>Cancel</button><button className="button oc-danger-button" onClick={() => void confirmRetirement()}>Retire Fighter</button></div></section></div>}
    {developing && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal" role="dialog" aria-modal="true" aria-labelledby="develop-oc-heading"><div className="oc-modal-heading"><div><p className="eyebrow">Develop Fighter</p><h2 id="develop-oc-heading">{developing.name}</h2><p>{developing.verse.name}</p></div><button onClick={() => setDeveloping(null)} aria-label="Close development panel">×</button></div><div className="oc-points-balance"><span>Progression Points</span><strong>{developing.progression_points}</strong></div>{developing.overall >= developing.overall_cap && developing.power_score >= developing.power_score_cap && <p className="oc-max-development">Max Development</p>}<div className="oc-upgrade-list"><article><div><span>Overall</span><strong>{developing.overall} / {developing.overall_cap}</strong></div>{developing.overall >= developing.overall_cap ? <p>OVR MAX</p> : <p>Next: {developing.overall} → {developing.overall + 1}<br />Cost: {getOverallUpgradeCost(developing.overall)} {getOverallUpgradeCost(developing.overall) === 1 ? 'point' : 'points'}</p>}<button className="button button-primary" disabled={developing.overall >= developing.overall_cap || developing.progression_points < getOverallUpgradeCost(developing.overall) || progression.pendingKey !== null} onClick={() => void develop('overall')}>{developing.overall >= developing.overall_cap ? 'OVR Max' : 'Increase OVR'}</button></article><article><div><span>Battle Power</span><strong>{formatPower(developing.power_score)} / {formatPower(developing.power_score_cap)}</strong></div>{developing.power_score >= developing.power_score_cap ? <p>POWER MAX</p> : <p>Next: {formatPower(developing.power_score)} → {formatPower(Math.min(developing.power_score + 50, developing.power_score_cap))}<br />Cost: 1 point</p>}<button className="button button-primary" disabled={developing.power_score >= developing.power_score_cap || developing.progression_points < 1 || progression.pendingKey !== null} onClick={() => void develop('power')}>{developing.power_score >= developing.power_score_cap ? 'Power Max' : 'Increase Power'}</button></article></div>{developmentMessage && <p className="oc-development-success" role="status">{developmentMessage}</p>}{actionError && <p className="error-message" role="alert">{actionError}</p>}</section></div>}
    {portraitCharacter && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal compact oc-portrait-modal" role="dialog" aria-modal="true" aria-labelledby="portrait-heading"><div className="oc-modal-heading"><div><p className="eyebrow">OC Portrait</p><h2 id="portrait-heading">{portraitCharacter.image_url ? 'Change Portrait' : 'Add Portrait'}</h2></div><button onClick={() => { setPortraitCharacter(null); choosePortrait(null) }} aria-label="Close portrait uploader">×</button></div><OCImage src={portraitPreview ?? portraitCharacter.image_url} name={portraitCharacter.name} className="oc-portrait-preview" /><label className="oc-file-picker">Choose JPG, PNG, or WebP<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePortrait(event.target.files?.[0] ?? null)} /></label><small>Maximum file size: 5 MB</small>{actionError && <p className="error-message" role="alert">{actionError}</p>}<div className="oc-modal-actions"><button className="button button-secondary" disabled={portraitPending} onClick={() => { setPortraitCharacter(null); choosePortrait(null) }}>Cancel</button><button className="button button-primary" disabled={!portraitFile || portraitPending} onClick={() => void savePortrait()}>{portraitPending ? 'Uploading...' : 'Save Portrait'}</button></div></section></div>}
  </main>
}
