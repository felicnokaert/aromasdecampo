// =====================================================================
// Aromas de Campo — conexión a la base y utilidades compartidas
// Las claves de abajo son PÚBLICAS (clave "publishable" de Supabase):
// la seguridad la da la base de datos (RLS), no esconder esta clave.
// =====================================================================
window.AROMAS_CONFIG = {
  url: 'https://censvpqswmnnvhjorlpk.supabase.co',
  key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNlbnN2cHFzd21ubnZoam9ybHBrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUzNzQ5NjMsImV4cCI6MjExMDk1MDk2M30.VadmVJgt3_LEQjJEBqN1sktZXmbRTYC3VzGBrnl-4Z4'
};

(function () {
  const cfg = window.AROMAS_CONFIG;
  const listo = cfg.url && !cfg.url.includes('XXXXXXXX') && window.supabase;
  window.db = listo ? window.supabase.createClient(cfg.url, cfg.key, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'aromas-admin' }
  }) : null;
  if (!listo) console.warn('[Aromas] Falta configurar la base en js/aromas.js');

  const fmt = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 0 });
  const MESES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  const DIAS = ['dom','lun','mar','mié','jue','vie','sáb'];

  const A = window.Aromas = {
    MESES, DIAS,
    pesos: n => '$' + fmt.format(Math.round(n || 0)),
    pesosCorto: n => n >= 1000 ? '$' + (Math.round(n / 100) / 10).toString().replace('.', ',') + 'k' : '$' + n,
    // Fechas siempre como 'YYYY-MM-DD' en hora local (sin líos de zona horaria)
    iso: d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'),
    fecha: s => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); },
    sumar: (s, n) => { const d = A.fecha(s); d.setDate(d.getDate() + n); return A.iso(d); },
    noches: (a, b) => Math.round((A.fecha(b) - A.fecha(a)) / 86400000),
    hoy: () => A.iso(new Date()),
    lindo: s => { const d = A.fecha(s); return DIAS[d.getDay()] + ' ' + d.getDate() + ' de ' + MESES[d.getMonth()]; },
    corto: s => { const d = A.fecha(s); return d.getDate() + '/' + (d.getMonth() + 1); },
    // Fotos: las del sitio ("fotos/...") o las subidas desde el panel (bucket "fotos")
    foto: r => !r ? '' : (/^(https?:|fotos\/|logo\/)/.test(r) ? r : cfg.url + '/storage/v1/object/public/fotos/' + r),
    esc: s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),

    // De dónde viene la visita: ?utm_source=instagram o el sitio que la mandó
    fuente() {
      try {
        const p = new URLSearchParams(location.search);
        const u = p.get('utm_source') || p.get('fuente');
        if (u) { sessionStorage.setItem('aromas-fuente', u.toLowerCase().slice(0, 30)); }
        const guardada = sessionStorage.getItem('aromas-fuente');
        if (guardada) return guardada;
        const r = document.referrer;
        if (!r || r.includes(location.host)) return 'directo';
        if (/instagram/i.test(r)) return 'instagram';
        if (/facebook|fb\.|messenger/i.test(r)) return 'facebook';
        if (/google/i.test(r)) return 'google';
        if (/tiktok/i.test(r)) return 'tiktok';
        if (/whatsapp|wa\.me/i.test(r)) return 'whatsapp';
        return new URL(r).hostname.replace('www.', '').slice(0, 30);
      } catch (e) { return 'directo'; }
    },

    // Estadísticas: una visita por sesión, y clics importantes
    track(tipo, detalle) {
      if (!window.db) return;
      try {
        if (tipo === 'visita') {
          if (sessionStorage.getItem('aromas-visita')) return;
          sessionStorage.setItem('aromas-visita', '1');
        }
      } catch (e) { /* modo privado */ }
      window.db.rpc('registrar_evento', { p_tipo: tipo, p_detalle: detalle || null, p_fuente: A.fuente() }).then(() => {}, () => {});
    },

    // Cualquier link a WhatsApp de la página cuenta como clic de WhatsApp
    escucharWhatsApp() {
      document.addEventListener('click', e => {
        const a = e.target.closest && e.target.closest('a[href*="wa.me"], a[href*="whatsapp.com"]');
        if (a) A.track('whatsapp', (a.getAttribute('aria-label') || a.textContent || '').trim().slice(0, 100));
      }, true);
    }
  };
})();
