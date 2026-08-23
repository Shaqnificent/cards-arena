import { supabase } from '../../../lib/supabase'

export function resolveOcImageSrc(src: string | null | undefined): string | null {
  if (!src) return null
  if (src.startsWith('/') || /^https?:\/\//.test(src)) return src
  return supabase.storage.from('oc-images').getPublicUrl(src).data.publicUrl
}
