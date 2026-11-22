// Lee un calendario .ics (Booking, Airbnb, etc.) y devuelve [{uid, entrada, salida, resumen}]
// Fechas en formato 'YYYY-MM-DD'. La salida es el día que se van (no ocupa noche).
export function leerIcs(texto) {
  const lineas = String(texto || '').replace(/\r\n?/g, '\n').replace(/\n[ \t]/g, '').split('\n'); // "desdoblar" líneas largas
  const eventos = [];
  let ev = null;
  const fecha = (v) => {
    const m = String(v || '').match(/(\d{4})(\d{2})(\d{2})/);
    return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
  };
  const sumarDia = (s) => { const d = new Date(s + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + 1); return d.toISOString().slice(0, 10); };
  for (const l of lineas) {
    if (l === 'BEGIN:VEVENT') { ev = {}; continue; }
    if (l === 'END:VEVENT') {
      if (ev && ev.entrada) {
        if (!ev.salida || ev.salida <= ev.entrada) ev.salida = sumarDia(ev.entrada);
        if (!ev.uid) ev.uid = ev.entrada + '_' + ev.salida;
        eventos.push(ev);
      }
      ev = null; continue;
    }
    if (!ev) continue;
    const i = l.indexOf(':'); if (i < 0) continue;
    const clave = l.slice(0, i).split(';')[0].toUpperCase(), valor = l.slice(i + 1).trim();
    if (clave === 'UID') ev.uid = valor;
    else if (clave === 'DTSTART') ev.entrada = fecha(valor);
    else if (clave === 'DTEND') ev.salida = fecha(valor);
    else if (clave === 'SUMMARY') ev.resumen = valor.replace(/\\,/g, ',').replace(/\\n/g, ' ').slice(0, 200);
  }
  return eventos;
}

// Arma un .ics con las fechas ocupadas (sin datos de huéspedes)
export function armarIcs(nombre, eventos) {
  const sinGuion = (s) => String(s).replace(/-/g, '');
  const ahora = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
  const out = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Aromas de Campo//Reservas//ES', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'X-WR-CALNAME:' + String(nombre).replace(/[\r\n,;]/g, ' ')];
  for (const e of eventos) {
    out.push('BEGIN:VEVENT', 'UID:' + e.uid + '@aromasdecampo', 'DTSTAMP:' + ahora,
      'DTSTART;VALUE=DATE:' + sinGuion(e.entrada), 'DTEND;VALUE=DATE:' + sinGuion(e.salida),
      'SUMMARY:' + (e.resumen || 'Reservado'), 'END:VEVENT');
  }
  out.push('END:VCALENDAR');
  return out.join('\r\n') + '\r\n';
}
