import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabasePublishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const supabaseConfigurationError = !supabaseUrl || !supabasePublishableKey
  ? 'Anime Arena is not configured. Add the public Supabase URL and publishable key to the deployment environment.'
  : null

export const supabase = createClient(
  supabaseUrl || 'http://127.0.0.1:54321',
  supabasePublishableKey || 'missing-public-key',
)
