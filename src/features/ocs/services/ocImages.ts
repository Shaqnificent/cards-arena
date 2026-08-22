import { supabase } from '../../../lib/supabase'

const BUCKET = 'oc-images'
const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])
const maxBytes = 5 * 1024 * 1024

export function validatePortrait(file: File): string | null {
  if (!allowedTypes.has(file.type)) return 'Portrait must be a JPG, PNG, or WebP image.'
  if (file.size > maxBytes) return 'Portrait must be smaller than 5 MB.'
  return null
}

function objectPathFromReference(url: string): string | null {
  const marker = `/storage/v1/object/public/${BUCKET}/`
  const index = url.indexOf(marker)
  if (index >= 0) return decodeURIComponent(url.slice(index + marker.length).split('?')[0] ?? '')
  return url.startsWith('http://') || url.startsWith('https://') ? null : url.split('?')[0] ?? null
}

export async function uploadOcPortrait(characterId: string, file: File, previousUrl: string | null): Promise<void> {
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError || !user) throw userError ?? new Error('Authentication required.')
  const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
  const path = `${user.id}/${characterId}/portrait-${Date.now()}.${extension}`
  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false })
  if (uploadError) throw uploadError
  const { error: rpcError } = await supabase.rpc('set_player_character_image', { p_character_id: characterId, p_image_path: path })
  if (rpcError) {
    await supabase.storage.from(BUCKET).remove([path])
    throw rpcError
  }
  const previousPath = previousUrl ? objectPathFromReference(previousUrl) : null
  if (previousPath && previousPath !== path) await supabase.storage.from(BUCKET).remove([previousPath])
}

export async function removeOcPortrait(characterId: string, imageUrl: string): Promise<void> {
  const { error } = await supabase.rpc('remove_player_character_image', { p_character_id: characterId })
  if (error) throw error
  const path = objectPathFromReference(imageUrl)
  if (path) await supabase.storage.from(BUCKET).remove([path])
}
