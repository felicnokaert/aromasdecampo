// Aromas de Campo — trae las reservas de Booking y Airbnb (links .ics) y las carga en el sistema.
// Corre sola cada 15 minutos (pg_cron) y también con el botón "Sincronizar ahora" del panel.
// Si aparece una doble reserva, manda un email a los avisos al instante.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { leerIcs } from "../_compartido/ical.js";
import { enviarEmail, plantilla, boton, esc } from "../_compartido/email.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: cals } = await db.from("calendarios_externos").select("*");
  const resultado: Record<string, unknown>[] = [];

  for (const c of cals || []) {
    try {
      const r = await fetch(c.url, { headers: { "User-Agent": "AromasDeCampo-Sync/1.0" }, signal: AbortSignal.timeout(20000) });
      if (!r.ok) throw new Error(`La plataforma respondió ${r.status}`);
      const texto = await r.text();
      if (!texto.includes("BEGIN:VCALENDAR")) throw new Error("El link no es un calendario .ics");
      const eventos = leerIcs(texto);
      const { data, error } = await db.rpc("sincronizar_eventos", { p_cal: c.id, p_eventos: eventos });
      if (error) throw error;
      resultado.push({ id: c.id, ...data });
    } catch (e) {
      const msg = (e as Error).message || String(e);
      const desde = c.error_desde || new Date().toISOString();
      await db.from("calendarios_externos").update({ ultimo_error: msg.slice(0, 300), ultima_sync: new Date().toISOString(), error_desde: desde }).eq("id", c.id);
      // si sigue fallando hace más de 3 horas, avisar (una sola vez por cada problema)
      if (Date.now() - new Date(desde).getTime() > 3 * 3600e3) {
        const { data: cab } = await db.from("cabanas").select("nombre").eq("id", c.cabana_id).single();
        const plat = c.plataforma === "booking" ? "Booking" : "Airbnb";
        await db.from("alertas").upsert({ clave: `sync:${c.id}:${desde}`, tipo: "sync",
          mensaje: `🔌 El calendario de ${plat} de ${cab?.nombre || "una cabaña"} no se puede leer hace más de 3 horas (${msg.slice(0, 120)}). Mientras tanto las fechas de ${plat} no llegan a la web: revisá el link en Más → Booking y Airbnb.` },
          { onConflict: "clave", ignoreDuplicates: true });
      }
      resultado.push({ id: c.id, error: msg });
    }
  }

  // avisos por email que todavía no se mandaron: dobles reservas, reservas nuevas o canceladas de las plataformas, calendarios caídos
  const { data: alertas } = await db.from("alertas").select("*").eq("enviada", false)
    .or("tipo.in.(doble,sync),clave.like.nueva:*,clave.like.cancel:*");
  if (alertas?.length) {
    const { data: aj } = await db.from("ajustes").select("email_avisos, web_url").single();
    const urgente = alertas.some((a) => a.tipo !== "aviso");
    const soloNuevas = alertas.every((a) => String(a.clave).startsWith("nueva:"));
    const asunto = urgente ? "⚠️ Aromas de Campo: revisá estas reservas"
      : soloNuevas ? (alertas.length > 1 ? `📅 ${alertas.length} reservas nuevas en Airbnb/Booking` : "📅 Nueva reserva en " + (String(alertas[0].clave).includes("airbnb") ? "Airbnb" : "Booking"))
      : "📅 Cambios en reservas de Airbnb/Booking";
    const color = (a: Record<string, unknown>) => a.tipo === "aviso" ? "#E6EEF7" : "#FBEAEA";
    const ok = await enviarEmail(aj?.email_avisos || "", asunto,
      plantilla(urgente ? "Atención con estas fechas" : "Novedades de las plataformas", alertas.map((a) => `<p style="background:${color(a)};padding:10px;border-radius:8px">${esc(a.mensaje)}</p>`).join("") +
        boton((aj?.web_url || "https://aromasdecampo.ar") + "/panel", "Abrir el panel")));
    if (ok) await db.from("alertas").update({ enviada: true }).in("id", alertas.map((a) => a.id));
  }

  return new Response(JSON.stringify({ ok: true, calendarios: resultado }), { headers: { ...cors, "Content-Type": "application/json" } });
});
