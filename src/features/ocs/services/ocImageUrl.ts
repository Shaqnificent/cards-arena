import { supabase } from '../../../lib/supabase'

export function resolveOcImageSrc(src: string | null | undefined): string | null {
  if (!src) return null
  return !/^https?:\/\//.test(src) ? supabase.storage.from('oc-images').getPublicUrl(src).data.publicUrl : src
}
