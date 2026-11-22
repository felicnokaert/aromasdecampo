// Aromas de Campo — trae las reservas de Booking y Airbnb (links .ics) y las carga en el sistema.
// Corre sola cada 30 minutos (pg_cron) y también con el botón "Sincronizar ahora" del panel.
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
      await db.from("calendarios_externos").update({ ultimo_error: msg.slice(0, 300), ultima_sync: new Date().toISOString() }).eq("id", c.id);
      resultado.push({ id: c.id, error: msg });
    }
  }

  // avisos urgentes por email (dobles reservas) que todavía no se mandaron
  const { data: alertas } = await db.from("alertas").select("*").eq("enviada", false).eq("tipo", "doble");
  if (alertas?.length) {
    const { data: aj } = await db.from("ajustes").select("email_avisos, web_url").single();
    const ok = await enviarEmail(aj?.email_avisos || "", "⚠️ Aromas de Campo: revisá estas reservas",
      plantilla("Atención con estas fechas", alertas.map((a) => `<p style="background:#FBEAEA;padding:10px;border-radius:8px">${esc(a.mensaje)}</p>`).join("") +
        boton((aj?.web_url || "") + "/admin.html", "Abrir el panel")));
    if (ok) await db.from("alertas").update({ enviada: true }).in("id", alertas.map((a) => a.id));
  }

  return new Response(JSON.stringify({ ok: true, calendarios: resultado }), { headers: { ...cors, "Content-Type": "application/json" } });
});
