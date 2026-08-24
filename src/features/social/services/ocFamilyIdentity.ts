import { supabase } from '../../../lib/supabase'
import type { OcFamilyIdentity, OcFamilyIdentityInput } from '../types'

const BUCKET = 'oc-family-logos'
const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])
const maxBytes = 3 * 1024 * 1024

export function validateFamilyLogo(file: File): string | null {
  if (!allowedTypes.has(file.type)) return 'Family logo must be a JPG, PNG, or WebP image.'
  if (file.size > maxBytes) return 'Family logo must be smaller than 3 MB.'
  return null
}

export function resolveFamilyLogoSrc(path: string | null | undefined, updatedAt?: string | null): string | null {
  if (!path) return null
  const source = path.startsWith('/') || /^https?:\/\//.test(path)
    ? path
    : supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
  const version = updatedAt ?? path
  return `${source}${source.includes('?') ? '&' : '?'}v=${encodeURIComponent(version)}`
}

export async function getMyOcFamilyIdentity(): Promise<OcFamilyIdentity | null> {
  const { data, error } = await supabase.rpc('get_my_oc_family_identity')
  if (error) throw error
  return data as OcFamilyIdentity | null
}

async function uploadFamilyLogo(ownerId: string, file: File): Promise<string> {
  const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
  const path = `${ownerId}/family-logo.${extension}`
  const { error } = await supabase.storage.from(BUCKET).upload(path, file, {
    cacheControl: '3600',
    contentType: file.type,
    upsert: true,
  })
  if (error) throw error
  return path
}

async function removeFamilyLogo(path: string): Promise<void> {
  const { error } = await supabase.storage.from(BUCKET).remove([path])
  if (error) throw error
}

export async function saveMyOcFamilyIdentity(
  ownerId: string,
  current: OcFamilyIdentity | null,
  input: OcFamilyIdentityInput,
): Promise<OcFamilyIdentity> {
  const oldLogoPath = current?.logoPath ?? null
  let nextLogoPath = input.removeLogo ? null : oldLogoPath
  let uploadedLogoPath: string | null = null

  if (input.logoFile) {
    uploadedLogoPath = await uploadFamilyLogo(ownerId, input.logoFile)
    nextLogoPath = uploadedLogoPath
  }

  const { data, error } = await supabase.rpc('upsert_oc_family_identity', {
    p_name: input.name,
    p_tagline: input.tagline,
    p_description: input.description,
    p_logo_path: nextLogoPath,
  })

  if (error) {
    if (uploadedLogoPath && uploadedLogoPath !== oldLogoPath) {
      try { await removeFamilyLogo(uploadedLogoPath) } catch (cleanupError) { console.error('Family logo rollback failed', cleanupError) }
    }
    throw error
  }

  if (oldLogoPath && oldLogoPath !== nextLogoPath) {
    try { await removeFamilyLogo(oldLogoPath) } catch (cleanupError) { console.error('Previous Family logo cleanup failed', cleanupError) }
  }

  return data as OcFamilyIdentity
}
