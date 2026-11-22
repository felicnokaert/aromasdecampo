// Link de calendario .ics por cabaña para Booking y Airbnb.
// /cal/booking/<token>.ics → todo lo ocupado MENOS lo que vino de Booking (para no devolverle sus propias reservas)
// /cal/airbnb/<token>.ics  → lo mismo para Airbnb · /cal/todo/<token>.ics → todo
// Solo fechas: nunca nombres ni datos de huéspedes.
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://censvpqswmnnvhjorlpk.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNlbnN2cHFzd21ubnZoam9ybHBrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUzNzQ5NjMsImV4cCI6MjExMDk1MDk2M30.VadmVJgt3_LEQjJEBqN1sktZXmbRTYC3VzGBrnl-4Z4';

function armarIcs(nombre, eventos) {
  const sinGuion = (x) => String(x).replace(/-/g, '');
  const ahora = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
  const out = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Aromas de Campo//Reservas//ES', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH', 'X-WR-CALNAME:' + nombre];
  for (const e of eventos) {
    out.push('BEGIN:VEVENT', 'UID:' + e.uid + '@aromasdecampo', 'DTSTAMP:' + ahora, 'DTSTART;VALUE=DATE:' + sinGuion(e.entrada),
      'DTEND;VALUE=DATE:' + sinGuion(e.salida), 'SUMMARY:' + (e.resumen || 'Reservado'), 'END:VEVENT');
  }
  out.push('END:VCALENDAR');
  return out.join('\r\n') + '\r\n';
}

module.exports = async (req, res) => {
  const para = String(req.query.para || 'todo').toLowerCase();
  const token = String(req.query.archivo || '').replace(/\.ics$/i, '');
  if (!/^[0-9a-f-]{36}$/i.test(token) || !['booking', 'airbnb', 'todo'].includes(para)) {
    res.status(404).send('Calendario no encontrado');
    return;
  }
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/ical_eventos', {
    method: 'POST',
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_token: token, p_excluir: para === 'todo' ? null : para })
  });
  if (!r.ok) { res.status(502).send('No se pudo leer el calendario'); return; }
  const eventos = await r.json();
  res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300');
  res.status(200).send(armarIcs('Aromas de Campo', eventos));
};
