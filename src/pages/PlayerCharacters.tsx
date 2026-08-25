import { useEffect, useMemo, useState } from 'react'
import { AppHeader } from '../components/AppHeader'
import { LoadoutNav } from '../components/LoadoutNav'
import { usePlayerCharacters } from '../features/ocs/hooks/usePlayerCharacters'
import { getGrowthType, type OcType, type PlayerCharacter } from '../features/ocs/types'
import { getOverallUpgradeCost } from '../features/ocs/types'
import { useOcProgression } from '../features/ocs/hooks/useOcProgression'
import { useVerses } from '../hooks/useVerses'
import { OCImage } from '../features/ocs/components/OCImage'
import { removeOcPortrait, uploadOcPortrait, validatePortrait } from '../features/ocs/services/ocImages'
import { isOcSelectableVerse } from '../lib/randomCharacterTheme'
import { useOcFamilyIdentity } from '../features/social/hooks/useOcFamilyIdentity'
import { FamilyLogo } from '../features/social/components/FamilyLogo'
import { validateFamilyLogo } from '../features/social/services/ocFamilyIdentity'

interface PlayerCharactersProps {
  currentUserId: string
  username: string
  avatarUrl: string | null
  isGuest: boolean
  isSystemPlayer: boolean
}

const formatPower = (value: number) => value.toLocaleString()
const MAX_ACTIVE_OCS = 5

function CharacterIdentity({ character }: { character: PlayerCharacter }) {
  return <div className="oc-identity">
    <OCImage src={character.image_url} name={character.name} className="oc-avatar" />
    <div><span>{character.verse.name}</span><h3>{character.name}</h3></div>
  </div>
}

function OcTypeBadge({ type }: { type: OcType }) { return <span className={`oc-type-badge ${type}`}>{type === 'champion' ? 'Champion' : 'Sacrificial'}</span> }

function LoreIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5h10.5A2.5 2.5 0 0 1 18 7v12.5H7.5A2.5 2.5 0 0 1 5 17V4.5Z" /><path d="M8 8h7M8 11.5h7M8 15h4.5M18 7h1v12.5h-1" /></svg>
}

function MoreIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="5" r="1.5" /><circle cx="12" cy="12" r="1.5" /><circle cx="12" cy="19" r="1.5" /></svg>
}

function EditIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14.5 5.5 4 4M4 20l3.8-.8L19 8a2.1 2.1 0 0 0-3-3L4.8 16.2 4 20Z" /></svg>
}

function AddIcon() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg>
}

function CreationFieldIcon({ type }: { type: 'name' | 'verse' | 'fighter' }) {
  if (type === 'name') return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4" /><path d="M4.5 21a7.5 7.5 0 0 1 15 0" /></svg>
  if (type === 'verse') return <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9S14.5 18.3 12 21c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3Z" /></svg>
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 3 6 6-2 2-6-6 2-2Zm14 0-6 6 2 2 6-6-2-2ZM7 13l4 4-4 4-4-4 4-4Zm10 0 4 4-4 4-4-4 4-4Z" /></svg>
}

export function PlayerCharacters({ currentUserId, username, avatarUrl, isGuest, isSystemPlayer }: PlayerCharactersProps) {
  const collection = usePlayerCharacters()
  const progression = useOcProgression()
  const { verses, loading: versesLoading, error: versesError } = useVerses()
  const canCustomizeFamily = !isGuest && !isSystemPlayer
  const familyIdentity = useOcFamilyIdentity(currentUserId, canCustomizeFamily)
  const [formOpen, setFormOpen] = useState(false)
  const [showRetired, setShowRetired] = useState(false)
  const [name, setName] = useState('')
  const [verseId, setVerseId] = useState('')
  const [ocType, setOcType] = useState<OcType | null>(null)
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
  const [typingCharacter, setTypingCharacter] = useState<PlayerCharacter | null>(null)
  const [legacyType, setLegacyType] = useState<OcType>('champion')
  const [loreCharacter, setLoreCharacter] = useState<PlayerCharacter | null>(null)
  const [loreDraft, setLoreDraft] = useState('')
  const [loreError, setLoreError] = useState<string | null>(null)
  const [loreMessage, setLoreMessage] = useState<string | null>(null)
  const [familyEditorOpen, setFamilyEditorOpen] = useState(false)
  const [familyName, setFamilyName] = useState('')
  const [familyTagline, setFamilyTagline] = useState('')
  const [familyDescription, setFamilyDescription] = useState('')
  const [familyLogoFile, setFamilyLogoFile] = useState<File | null>(null)
  const [familyLogoPreview, setFamilyLogoPreview] = useState<string | null>(null)
  const [removeFamilyLogo, setRemoveFamilyLogo] = useState(false)
  const [familyError, setFamilyError] = useState<string | null>(null)
  const [familyMessage, setFamilyMessage] = useState<string | null>(null)
  const [openCardMenuId, setOpenCardMenuId] = useState<string | null>(null)

  useEffect(() => () => {
    if (familyLogoPreview) URL.revokeObjectURL(familyLogoPreview)
  }, [familyLogoPreview])

  useEffect(() => {
    if (!openCardMenuId) return
    const closeOnOutsideClick = (event: PointerEvent) => {
      if (!(event.target instanceof Element) || !event.target.closest('[data-oc-card-menu]')) setOpenCardMenuId(null)
    }
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpenCardMenuId(null)
    }
    document.addEventListener('pointerdown', closeOnOutsideClick)
    document.addEventListener('keydown', closeOnEscape)
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsideClick)
      document.removeEventListener('keydown', closeOnEscape)
    }
  }, [openCardMenuId])

  const ocSelectableVerses = useMemo(() => verses.filter(isOcSelectableVerse), [verses])
  const active = useMemo(() => collection.characters.filter((character) => character.active), [collection.characters])
  const retired = useMemo(() => collection.characters.filter((character) => !character.active), [collection.characters])
  const equipped = active.filter((character) => character.equipped)
  const championCount = equipped.filter((character) => character.oc_type === 'champion').length
  const sacrificialCount = equipped.length - championCount
  const familyComposition = equipped.length === 0 ? 'Up to three fighters' : `${championCount} Champion${championCount === 1 ? '' : 's'}${sacrificialCount ? ` / ${sacrificialCount} Sacrificial` : ''}`
  const selectedVerseId = String(verseId || ocSelectableVerses[0]?.id || '')
  const collectionAtCapacity = active.length >= MAX_ACTIVE_OCS
  const familyDisplayName = familyIdentity.identity?.name ?? `${username}'s OC Family`

  const openCreation = () => {
    if (collectionAtCapacity) return setActionError('Your OC collection is full. Retire one fighter before creating another.')
    if (ocSelectableVerses.length === 0) return setActionError('No OC-selectable verses are currently available.')
    setActionError(null); setCreated(null); setName(''); setVerseId(ocSelectableVerses[0]?.id ?? ''); setOcType(null); setFormOpen(true)
  }

  const submitCreation = async () => {
    const normalizedName = name.trim()
    if (normalizedName.length < 2 || normalizedName.length > 50) return setActionError('OC name must be between 2 and 50 characters.')
    const verse = ocSelectableVerses.find((option) => String(option.id) === selectedVerseId)
    if (!verse) return setActionError('Select an active OC verse.')
    if (!ocType) return setActionError('Choose a permanent fighter type.')
    setActionError(null)
    try { setCreated(await collection.create({ name: normalizedName, verse, ocType })) }
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

  const confirmLegacyType = async () => {
    if (!typingCharacter) return
    setActionError(null)
    try { await collection.selectType(typingCharacter, legacyType); setTypingCharacter(null) }
    catch (error) { setActionError(error instanceof Error ? error.message : 'Unable to set this fighter type.') }
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

  const openLoreEditor = (character: PlayerCharacter) => {
    setLoreCharacter(character)
    setLoreDraft(character.lore ?? '')
    setLoreError(null)
    setLoreMessage(null)
  }

  const openPortraitEditor = (character: PlayerCharacter) => {
    setPortraitCharacter(character)
    setPortraitFile(null)
    setPortraitPreview(null)
    setActionError(null)
  }

  const saveLore = async () => {
    if (!loreCharacter || collection.pendingId === loreCharacter.id) return
    if (loreDraft.length > 1000) return setLoreError('OC lore cannot exceed 1000 characters.')
    setLoreError(null)
    try {
      const characterName = loreCharacter.name
      await collection.updateLore(loreCharacter, loreDraft)
      setLoreCharacter(null)
      setLoreDraft('')
      setLoreMessage(loreDraft.trim() ? `Background saved for ${characterName}.` : `Background cleared for ${characterName}.`)
    } catch (error) {
      setLoreError(error instanceof Error ? error.message : 'Unable to save this OC background.')
    }
  }

  const openFamilyEditor = () => {
    if (!canCustomizeFamily || familyIdentity.loading) return
    setFamilyName(familyIdentity.identity?.name ?? '')
    setFamilyTagline(familyIdentity.identity?.tagline ?? '')
    setFamilyDescription(familyIdentity.identity?.description ?? '')
    setFamilyLogoFile(null)
    setFamilyLogoPreview(null)
    setRemoveFamilyLogo(false)
    setFamilyError(null)
    setFamilyMessage(null)
    setFamilyEditorOpen(true)
  }

  const closeFamilyEditor = () => {
    if (familyIdentity.pending) return
    setFamilyEditorOpen(false)
    setFamilyLogoFile(null)
    setFamilyLogoPreview(null)
    setRemoveFamilyLogo(false)
    setFamilyError(null)
  }

  const chooseFamilyLogo = (file: File | null) => {
    setFamilyLogoFile(null)
    setFamilyLogoPreview(null)
    setFamilyError(null)
    if (!file) return
    const validation = validateFamilyLogo(file)
    if (validation) return setFamilyError(validation)
    setFamilyLogoFile(file)
    setFamilyLogoPreview(URL.createObjectURL(file))
    setRemoveFamilyLogo(false)
  }

  const saveFamilyIdentity = async () => {
    if (familyIdentity.pending) return
    if (familyName.trim().length > 40) return setFamilyError('Family name cannot exceed 40 characters.')
    if (familyTagline.trim().length > 100) return setFamilyError('Family tagline cannot exceed 100 characters.')
    if (familyDescription.trim().length > 750) return setFamilyError('Family description cannot exceed 750 characters.')
    setFamilyError(null)
    try {
      await familyIdentity.save({
        name: familyName,
        tagline: familyTagline,
        description: familyDescription,
        logoFile: familyLogoFile,
        removeLogo: removeFamilyLogo,
      })
      setFamilyMessage('Your OC Family identity has been saved.')
      setFamilyEditorOpen(false)
      setFamilyLogoFile(null)
      setFamilyLogoPreview(null)
      setRemoveFamilyLogo(false)
    } catch (error) {
      setFamilyError(error instanceof Error ? error.message : 'Unable to save your OC Family right now.')
    }
  }

  return <main className="oc-page">
    <AppHeader active="loadout" username={username} avatarUrl={avatarUrl} />
    <section className="oc-content" aria-labelledby="oc-heading">
      <LoadoutNav active="ocs" />
      <header className="oc-hero"><div><p className="eyebrow">My Fighters</p><h1 id="oc-heading">OC Family</h1><p>Create and develop your own fighters across the Anime Arena universes.</p></div><div className="oc-hero-actions"><span className="oc-collection-count">{active.length} / {MAX_ACTIVE_OCS}<small>Collection</small></span><strong>{equipped.length} / 3 <small>Equipped</small></strong>{canCustomizeFamily && <button className="button button-secondary oc-customize-family oc-hero-icon-button" title={familyIdentity.identity ? 'Edit Family' : 'Customize Family'} aria-label={familyIdentity.identity ? 'Edit OC Family' : 'Customize OC Family'} onClick={openFamilyEditor} disabled={familyIdentity.loading}><EditIcon /></button>}<button className="button button-primary oc-hero-icon-button" title={collectionAtCapacity ? 'OC collection is full' : 'Create OC'} aria-label={collectionAtCapacity ? 'OC collection is full' : 'Create OC'} onClick={openCreation} disabled={versesLoading || Boolean(versesError) || ocSelectableVerses.length === 0 || collectionAtCapacity}><AddIcon /></button></div></header>

      {actionError && <p className="oc-message error-message" role="alert">{actionError}</p>}
      {loreMessage && <p className="oc-message oc-success-message" role="status">{loreMessage}</p>}
      {familyMessage && <p className="oc-message oc-success-message" role="status">{familyMessage}</p>}
      {familyIdentity.error && <p className="oc-message error-message" role="alert">{familyIdentity.error}</p>}
      {progression.error && <p className="oc-message error-message" role="alert">{progression.error}</p>}
      {(collection.error || versesError) && <div className="catalogue-state oc-state" role="alert"><h2>Unable to load OC data</h2><p>{collection.error ?? 'Unable to load active verses.'}</p><button className="button button-secondary" onClick={() => void collection.refresh()}>Retry</button></div>}

      {!collection.error && !versesError && <>
        {!progression.loading && progression.rewards.length > 0 && <section className="oc-rewards" aria-labelledby="rewards-heading"><div><p className="eyebrow">Unclaimed Progression</p><h2 id="rewards-heading">You have {progression.rewards.length} {progression.rewards.length === 1 ? 'reward' : 'rewards'} waiting</h2></div><div className="oc-reward-list">{progression.rewards.map((reward) => <article key={reward.id}><div><strong>Local Match Win</strong><span>+{reward.points} points</span></div><select aria-label="Assign reward to OC" value={rewardTargets[reward.id] || active[0]?.id || ''} disabled={active.length === 0} onChange={(event) => setRewardTargets((current) => ({ ...current, [reward.id]: event.target.value }))}><option value="" disabled>Choose a fighter</option>{active.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}</select><button className="button button-primary" disabled={active.length === 0 || progression.pendingKey === `claim:${reward.id}`} onClick={() => void claimReward(reward.id)}>Assign to OC</button></article>)}</div></section>}
        <section className="oc-section" aria-labelledby="family-heading"><div className="oc-section-heading"><div><p className="eyebrow">Active OC Family</p><h2 id="family-heading">Match Loadout</h2></div><span>{familyComposition}</span></div>
          <div className="oc-family-grid">{Array.from({ length: 3 }, (_, index) => {
            const character = equipped[index]
            return character ? <article className="oc-family-slot filled" key={character.id}><span className="oc-slot-label">Slot {index + 1}</span><OCImage src={character.image_url} name={character.name} className="oc-family-portrait" /><CharacterIdentity character={character} /><OcTypeBadge type={character.oc_type} /><div className="oc-slot-stats"><b>{character.overall} <small>OVR</small></b><b>{formatPower(character.power_score)} <small>Power</small></b></div><div className="oc-portrait-actions"><button className="button button-secondary" onClick={() => { setPortraitCharacter(character); setPortraitFile(null); setPortraitPreview(null); setActionError(null) }}>{character.image_url ? 'Change Portrait' : 'Add Portrait'}</button>{character.image_url && <button className="text-button" disabled={portraitPending} onClick={() => void removePortrait(character)}>Remove</button>}</div></article>
              : <div className="oc-family-slot empty" key={`empty-${index}`}><span>+</span><strong>Empty Slot</strong><small>Equip an OC from your collection</small></div>
          })}</div>
        </section>

        <section className="oc-section" aria-labelledby="collection-heading"><div className="oc-section-heading"><div><p className="eyebrow">Your Fighters</p><h2 id="collection-heading">OC Collection</h2></div></div>
          {collection.loading ? <div className="catalogue-state oc-state"><h2>Loading your OC family...</h2></div>
            : active.length === 0 ? <div className="catalogue-state oc-state"><h2>No OC fighters yet.</h2><p>Create your first fighter and discover their potential.</p><button className="button button-primary" onClick={openCreation}>Create Your First OC</button></div>
            : <div className="oc-collection-grid">{active.map((character) => {
              const menuOpen = openCardMenuId === character.id
              const pending = collection.pendingId === character.id
              return <article className={`oc-card${character.equipped ? ' equipped' : ''}`} key={character.id}>
                <div className="oc-card-heading-row">
                  <CharacterIdentity character={character} />
                  <div className="oc-card-utilities">
                    <button className="oc-card-icon-button" type="button" title={character.lore ? 'Edit Lore' : 'Add Lore'} aria-label={`${character.lore ? 'Edit' : 'Add'} lore for ${character.name}`} onClick={() => openLoreEditor(character)}><LoreIcon /></button>
                    <div className="oc-card-menu" data-oc-card-menu>
                      <button className="oc-card-icon-button" type="button" title="More actions" aria-label={`More actions for ${character.name}`} aria-expanded={menuOpen} aria-haspopup="menu" aria-controls={`oc-card-menu-${character.id}`} onClick={() => setOpenCardMenuId(menuOpen ? null : character.id)}><MoreIcon /></button>
                      {menuOpen && <div className="oc-card-overflow" id={`oc-card-menu-${character.id}`} role="menu" aria-label={`Actions for ${character.name}`}>
                        <button type="button" role="menuitem" onClick={() => { setOpenCardMenuId(null); setDeveloping(character); setDevelopmentMessage(null); setActionError(null) }}>Develop</button>
                        <button type="button" role="menuitem" disabled={!character.equipped} title={character.equipped ? undefined : 'Equip this OC before updating its portrait'} onClick={() => { setOpenCardMenuId(null); openPortraitEditor(character) }}>{character.image_url ? 'Update Portrait' : 'Add Portrait'}{!character.equipped ? ' · Equip first' : ''}</button>
                        <button className="destructive" type="button" role="menuitem" disabled={pending} onClick={() => { setOpenCardMenuId(null); setRetiring(character) }}>Retire OC</button>
                      </div>}
                    </div>
                  </div>
                </div>
                <div className="oc-card-badges"><span className="oc-growth">{getGrowthType(character.starting_overall)}</span><OcTypeBadge type={character.oc_type} /></div>
                {!character.type_selected_at && <button className="text-button oc-legacy-type" onClick={() => { setTypingCharacter(character); setLegacyType(character.oc_type) }}>Choose permanent type</button>}
                <div className="oc-stat-grid"><div><span>Current OVR</span><strong>{character.overall} <small>/ {character.overall_cap}</small></strong></div><div><span>Battle Power</span><strong>{formatPower(character.power_score)} <small>/ {formatPower(character.power_score_cap)}</small></strong></div><div><span>Starting OVR</span><strong>{character.starting_overall}</strong></div><div><span>Progression Points</span><strong>{character.progression_points}</strong></div></div>
                <div className="oc-card-actions">
                  <button className={`button ${character.equipped ? 'oc-unequip-button' : 'button-primary'}`} disabled={pending} onClick={() => void toggleEquipped(character)}>{character.equipped ? 'Unequip' : 'Equip'}</button>
                </div>
              </article>
            })}</div>}
        </section>

        {retired.length > 0 && <section className="oc-retired"><button className="text-button" onClick={() => setShowRetired((value) => !value)} aria-expanded={showRetired}>Retired OCs ({retired.length}) <span>{showRetired ? '−' : '+'}</span></button>{showRetired && <div className="oc-retired-list">{retired.map((character) => <article key={character.id}><CharacterIdentity character={character} /><span>{character.overall} OVR</span><span>{formatPower(character.power_score)} Power</span><time dateTime={character.retired_at ?? ''}>Retired {character.retired_at ? new Date(character.retired_at).toLocaleDateString() : '—'}</time><button className="text-button oc-retired-lore-button" onClick={() => openLoreEditor(character)}>{character.lore ? 'Edit Lore' : 'Add Lore'}</button></article>)}</div>}</section>}
      </>}
    </section>

    {formOpen && <div className="oc-modal-backdrop" role="presentation"><section className={`oc-modal${created ? '' : ' create-oc-modal'}`} role="dialog" aria-modal="true" aria-labelledby="create-oc-heading">{created ? <div className="oc-reveal"><p className="eyebrow">Character Created</p><CharacterIdentity character={created} /><p>Your potential has been determined</p><div className="oc-reveal-stats"><div><span>Starting OVR</span><strong>{created.starting_overall}</strong></div><div><span>Growth Type</span><strong>{getGrowthType(created.starting_overall)}</strong></div><div><span>OVR Cap</span><strong>{created.overall_cap}</strong></div><div><span>Battle Power</span><strong>{formatPower(created.power_score)}</strong></div><div><span>Power Cap</span><strong>{formatPower(created.power_score_cap)}</strong></div></div><button className="button button-primary" onClick={() => setFormOpen(false)}>View My Fighter</button></div>
        : <><div className="oc-modal-heading"><div><p className="eyebrow">New Fighter</p><h2 id="create-oc-heading">Create OC</h2></div><button onClick={() => setFormOpen(false)} aria-label="Close creation form">&times;</button></div><label className="create-oc-field"><span><CreationFieldIcon type="name" />OC Name</span><input maxLength={50} value={name} onChange={(event) => setName(event.target.value)} placeholder="Enter fighter name" /></label><label className="create-oc-field"><span><CreationFieldIcon type="verse" />Verse</span><select value={selectedVerseId} onChange={(event) => setVerseId(event.target.value)}><option value="" disabled>Select a verse</option>{ocSelectableVerses.map((verse) => <option key={verse.id} value={verse.id}>{verse.name}</option>)}</select></label><fieldset className="oc-type-picker create-oc-type-picker"><legend><CreationFieldIcon type="fighter" />Fighter Type</legend><button type="button" className={ocType === 'champion' ? 'selected' : ''} aria-pressed={ocType === 'champion'} onClick={() => setOcType('champion')}><span className="oc-type-check" aria-hidden="true">{ocType === 'champion' ? '✓' : ''}</span><strong>Champion</strong><span>Best for direct combat. Absorb a same-verse drafted fighter to raise your OC's temporary OVR.</span></button><button type="button" className={ocType === 'sacrificial' ? 'selected' : ''} aria-pressed={ocType === 'sacrificial'} onClick={() => setOcType('sacrificial')}><span className="oc-type-check" aria-hidden="true">{ocType === 'sacrificial' ? '✓' : ''}</span><strong>Sacrificial</strong><span>Best for support. Give up this OC to increase the Battle Power of every drafted fighter from the same verse.</span></button><small><i aria-hidden="true">i</i>Your OC Type affects how the character can be used in matches. This choice is permanent.</small></fieldset>{actionError && <p className="error-message" role="alert">{actionError}</p>}<div className="oc-modal-actions"><button className="button button-secondary" onClick={() => setFormOpen(false)}>Cancel</button><button className="button button-primary" disabled={!ocType || collection.pendingId === 'create'} onClick={() => void submitCreation()}>{collection.pendingId === 'create' ? 'Evaluating Potential...' : <>Create Fighter <span className="create-fighter-sparkle" aria-hidden="true">✦</span></>}</button></div></>}</section></div>}

    {retiring && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal compact" role="alertdialog" aria-modal="true" aria-labelledby="retire-oc-heading"><p className="eyebrow">Retire Fighter</p><h2 id="retire-oc-heading">Retire {retiring.name}?</h2><p>This fighter will leave your active collection and cannot be used in new matches.</p><div className="oc-modal-actions"><button className="button button-secondary" onClick={() => setRetiring(null)}>Cancel</button><button className="button oc-danger-button" onClick={() => void confirmRetirement()}>Retire Fighter</button></div></section></div>}
    {developing && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal" role="dialog" aria-modal="true" aria-labelledby="develop-oc-heading"><div className="oc-modal-heading"><div><p className="eyebrow">Develop Fighter</p><h2 id="develop-oc-heading">{developing.name}</h2><p>{developing.verse.name}</p></div><button onClick={() => setDeveloping(null)} aria-label="Close development panel">×</button></div><div className="oc-points-balance"><span>Progression Points</span><strong>{developing.progression_points}</strong></div>{developing.overall >= developing.overall_cap && developing.power_score >= developing.power_score_cap && <p className="oc-max-development">Max Development</p>}<div className="oc-upgrade-list"><article><div><span>Overall</span><strong>{developing.overall} / {developing.overall_cap}</strong></div>{developing.overall >= developing.overall_cap ? <p>OVR MAX</p> : <p>Next: {developing.overall} → {developing.overall + 1}<br />Cost: {getOverallUpgradeCost(developing.overall)} {getOverallUpgradeCost(developing.overall) === 1 ? 'point' : 'points'}</p>}<button className="button button-primary" disabled={developing.overall >= developing.overall_cap || developing.progression_points < getOverallUpgradeCost(developing.overall) || progression.pendingKey !== null} onClick={() => void develop('overall')}>{developing.overall >= developing.overall_cap ? 'OVR Max' : 'Increase OVR'}</button></article><article><div><span>Battle Power</span><strong>{formatPower(developing.power_score)} / {formatPower(developing.power_score_cap)}</strong></div>{developing.power_score >= developing.power_score_cap ? <p>POWER MAX</p> : <p>Next: {formatPower(developing.power_score)} → {formatPower(Math.min(developing.power_score + 50, developing.power_score_cap))}<br />Cost: 1 point</p>}<button className="button button-primary" disabled={developing.power_score >= developing.power_score_cap || developing.progression_points < 1 || progression.pendingKey !== null} onClick={() => void develop('power')}>{developing.power_score >= developing.power_score_cap ? 'Power Max' : 'Increase Power'}</button></article></div>{developmentMessage && <p className="oc-development-success" role="status">{developmentMessage}</p>}{actionError && <p className="error-message" role="alert">{actionError}</p>}</section></div>}
    {portraitCharacter && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal compact oc-portrait-modal" role="dialog" aria-modal="true" aria-labelledby="portrait-heading"><div className="oc-modal-heading"><div><p className="eyebrow">OC Portrait</p><h2 id="portrait-heading">{portraitCharacter.image_url ? 'Change Portrait' : 'Add Portrait'}</h2></div><button onClick={() => { setPortraitCharacter(null); choosePortrait(null) }} aria-label="Close portrait uploader">×</button></div><OCImage src={portraitPreview ?? portraitCharacter.image_url} name={portraitCharacter.name} className="oc-portrait-preview" /><label className="oc-file-picker">Choose JPG, PNG, or WebP<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => choosePortrait(event.target.files?.[0] ?? null)} /></label><small>Maximum file size: 5 MB</small>{actionError && <p className="error-message" role="alert">{actionError}</p>}<div className="oc-modal-actions"><button className="button button-secondary" disabled={portraitPending} onClick={() => { setPortraitCharacter(null); choosePortrait(null) }}>Cancel</button><button className="button button-primary" disabled={!portraitFile || portraitPending} onClick={() => void savePortrait()}>{portraitPending ? 'Uploading...' : 'Save Portrait'}</button></div></section></div>}
    {loreCharacter && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal oc-lore-editor" role="dialog" aria-modal="true" aria-labelledby="lore-editor-heading"><div className="oc-modal-heading"><div><p className="eyebrow">Lore / Background</p><h2 id="lore-editor-heading">{loreCharacter.name}</h2><p>{loreCharacter.verse.name} · {loreCharacter.oc_type === 'champion' ? 'Champion' : 'Sacrificial'}</p></div><button onClick={() => setLoreCharacter(null)} aria-label="Close lore editor">&times;</button></div><label><span>Character background</span><textarea value={loreDraft} maxLength={1000} onChange={(event) => setLoreDraft(event.target.value)} placeholder="Write a short background for this OC..." /></label><div className="oc-lore-editor-meta"><span>Plain text only</span><strong className={loreDraft.length >= 950 ? 'near-limit' : undefined}>{loreDraft.length} / 1000</strong></div>{loreError && <p className="error-message" role="alert">{loreError}</p>}<div className="oc-modal-actions"><button className="button button-secondary" disabled={collection.pendingId === loreCharacter.id} onClick={() => setLoreCharacter(null)}>Cancel</button><button className="button button-primary" disabled={collection.pendingId === loreCharacter.id} onClick={() => void saveLore()}>{collection.pendingId === loreCharacter.id ? 'Saving...' : 'Save Background'}</button></div></section></div>}
    {familyEditorOpen && <div className="oc-modal-backdrop" role="presentation">
      <section className="oc-modal oc-family-editor" role="dialog" aria-modal="true" aria-labelledby="family-editor-heading">
        <div className="oc-modal-heading">
          <div><p className="eyebrow">Family Identity</p><h2 id="family-editor-heading">Customize OC Family</h2><p>Give your active fighters a shared identity.</p></div>
          <button onClick={closeFamilyEditor} aria-label="Close Family editor">&times;</button>
        </div>
        <div className="family-logo-editor">
          <div className="family-logo-editor-preview">
            {familyLogoPreview
              ? <img src={familyLogoPreview} alt="New Family logo preview" />
              : <FamilyLogo logoPath={removeFamilyLogo ? null : familyIdentity.identity?.logoPath ?? null} updatedAt={familyIdentity.identity?.updatedAt} name={familyName.trim() || familyDisplayName} />}
          </div>
          <div>
            <label className="family-logo-picker">Choose Logo<input key={familyLogoPreview ?? (removeFamilyLogo ? 'removed' : familyIdentity.identity?.logoPath ?? 'empty')} type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => chooseFamilyLogo(event.target.files?.[0] ?? null)} /></label>
            <small>JPG, PNG, or WebP. Maximum 3 MB.</small>
            {(familyLogoFile || (!removeFamilyLogo && familyIdentity.identity?.logoPath)) && <button type="button" className="text-button" onClick={() => { setFamilyLogoFile(null); setFamilyLogoPreview(null); setRemoveFamilyLogo(true) }}>Remove Logo</button>}
          </div>
        </div>
        <label><span>Family name</span><input value={familyName} maxLength={40} onChange={(event) => setFamilyName(event.target.value)} placeholder={`${username}'s OC Family`} /></label>
        <div className="oc-family-editor-count"><span>Optional</span><strong className={familyName.length >= 38 ? 'near-limit' : undefined}>{familyName.length} / 40</strong></div>
        <label><span>Tagline</span><input value={familyTagline} maxLength={100} onChange={(event) => setFamilyTagline(event.target.value)} placeholder="A short motto for your Family" /></label>
        <div className="oc-family-editor-count"><span>Optional</span><strong className={familyTagline.length >= 95 ? 'near-limit' : undefined}>{familyTagline.length} / 100</strong></div>
        <label><span>Description</span><textarea value={familyDescription} maxLength={750} onChange={(event) => setFamilyDescription(event.target.value)} placeholder="Describe what your OC Family represents..." /></label>
        <div className="oc-family-editor-count"><span>Plain text only</span><strong className={familyDescription.length >= 700 ? 'near-limit' : undefined}>{familyDescription.length} / 750</strong></div>
        {familyError && <p className="error-message" role="alert">{familyError}</p>}
        <div className="oc-modal-actions"><button className="button button-secondary" disabled={familyIdentity.pending} onClick={closeFamilyEditor}>Cancel</button><button className="button button-primary" disabled={familyIdentity.pending} onClick={() => void saveFamilyIdentity()}>{familyIdentity.pending ? 'Saving...' : 'Save Family'}</button></div>
      </section>
    </div>}
    {typingCharacter && <div className="oc-modal-backdrop" role="presentation"><section className="oc-modal compact" role="alertdialog" aria-modal="true" aria-labelledby="type-heading"><p className="eyebrow">One-Time Choice</p><h2 id="type-heading">Choose {typingCharacter.name}'s permanent type</h2><div className="oc-type-picker"><button type="button" className={legacyType === 'champion' ? 'selected' : ''} onClick={() => setLegacyType('champion')}><strong>Champion</strong><span>Direct fighter with Reserve or Absorb options.</span></button><button type="button" className={legacyType === 'sacrificial' ? 'selected' : ''} onClick={() => setLegacyType('sacrificial')}><strong>Sacrificial</strong><span>Support-only fighter that can empower its same-verse team.</span></button></div><p>This cannot be changed after confirmation.</p><div className="oc-modal-actions"><button className="button button-secondary" onClick={() => setTypingCharacter(null)}>Cancel</button><button className="button button-primary" disabled={collection.pendingId === typingCharacter.id} onClick={() => void confirmLegacyType()}>Confirm Permanent Type</button></div></section></div>}
  </main>
}
