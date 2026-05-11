// ================================================================
// Aromas de Campo — Supabase Client (compartido)
// Las keys se inyectan desde el HTML antes de cargar este script:
//   window.SUPABASE_URL      = 'https://XXXXXXXX.supabase.co'
//   window.SUPABASE_ANON_KEY = 'eyJ...'
// ================================================================

(function () {
  const url = window.SUPABASE_URL;
  const key = window.SUPABASE_ANON_KEY;

  if (!url || !key || url.includes('XXXXXXXX')) {
    console.warn('[Aromas] Supabase no configurado. Editá js/supabase-client.js con tus keys.');
    window.db = null;
    return;
  }

  window.db = window.supabase.createClient(url, key, {
    auth: { persistSession: true, autoRefreshToken: true }
  });
})();
