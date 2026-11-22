// Aromas de Campo — tareas automáticas de todos los días (10 de la mañana):
//  1. Recordatorio al huésped 2 días antes de llegar (cómo llegar, horarios, qué llevar). Sin clave de WiFi.
//  2. Pedido de reseña al día siguiente de irse, con su link personal.
//  3. Los lunes: resumen semanal para Rubén.
// 1 y 2 salen por email solo cuando hay dominio propio verificado (EMAIL_DESDE). Mientras tanto,
// el panel los muestra en "Para hacer hoy" con el WhatsApp ya escrito.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { enviarEmail, puedeEscribirHuespedes, plantilla, boton, esc, pesos, lindo, hoyAR } from "../_compartido/email.ts";

Deno.serve(async (_req) => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: aj } = await db.from("ajustes").select("*").single();
  const { data: cabs } = await db.from("cabanas").select("id, nombre");
  const cab = (id: number) => cabs?.find((c) => c.id === id)?.nombre || "";
  const web = aj?.web_url || "https://aromasdecampo.vercel.app";
  const hecho: Record<string, number | boolean> = {};

  // 1. Recordatorios de llegada
  if (puedeEscribirHuespedes()) {
    const { data: llegan } = await db.from("reservas").select("*").eq("estado", "confirmada").eq("entrada", hoyAR(2))
      .eq("recordatorio_enviado", false).not("email", "is", null);
    hecho.recordatorios = 0;
    for (const r of llegan || []) {
      const ok = await enviarEmail(r.email, `Te esperamos el ${lindo(r.entrada)} 🌿`, plantilla(`¡Ya falta poco, ${esc(String(r.nombre || "").split(" ")[0])}!`, `
        <p>Te esperamos en la cabaña <b>${esc(cab(r.cabana_id))}</b> el <b>${lindo(r.entrada)}</b> desde las ${esc(aj?.checkin)}. La salida es el ${lindo(r.salida)} hasta las ${esc(aj?.checkout)}.</p>
        ${aj?.info_llegada ? `<div style="background:#F0EBE1;padding:12px;border-radius:10px;white-space:pre-line">${esc(aj.info_llegada)}</div>` : ""}
        <p>Cualquier cosa, escribinos.</p>${boton(`https://wa.me/${aj?.whatsapp}`, "Escribir por WhatsApp", "#25D366")}`));
      if (ok) { await db.from("reservas").update({ recordatorio_enviado: true }).eq("id", r.id); (hecho.recordatorios as number)++; }
    }

    // 2. Pedido de reseña
    const { data: salieron } = await db.from("reservas").select("*").eq("estado", "confirmada").eq("salida", hoyAR(-1))
      .eq("resena_pedida", false).not("email", "is", null).in("origen", ["web", "whatsapp", "instagram", "otro"]);
    hecho.resenas = 0;
    for (const r of salieron || []) {
      const ok = await enviarEmail(r.email, "¿Cómo la pasaste en Aromas de Campo? ⭐", plantilla(`Gracias por venir, ${esc(String(r.nombre || "").split(" ")[0])}`, `
        <p>Esperamos que hayas descansado en la cabaña <b>${esc(cab(r.cabana_id))}</b>. ¿Nos contás cómo la pasaste? Nos lleva 1 minuto y ayuda muchísimo a otras familias a elegirnos.</p>
        ${boton(`${web}/opinar.html?c=${r.codigo}`, "Dejar mi opinión ⭐")}`));
      if (ok) { await db.from("reservas").update({ resena_pedida: true }).eq("id", r.id); (hecho.resenas as number)++; }
    }
  }

  // 3. Resumen semanal (lunes)
  const lunes = new Date(Date.now() - 3 * 3600e3).getUTCDay() === 1;
  // una sola vez por lunes, aunque la función se llame varias veces
  const yaMandado = lunes ? (await db.from("alertas").insert({ clave: "resumen:" + hoyAR(0), tipo: "aviso", mensaje: "Resumen semanal enviado", vista: true, enviada: true })).error : true;
  if (lunes && aj?.resumen_semanal && !yaMandado) {
    const desde7 = new Date(Date.now() - 7 * 86400e3).toISOString();
    const [semana, pend, visitas, wa, res, ingresos] = await Promise.all([
      db.from("reservas").select("*").eq("estado", "confirmada").gte("entrada", hoyAR(0)).lte("entrada", hoyAR(7)).order("entrada"),
      db.from("reservas").select("*").eq("estado", "pendiente").gte("creada", desde7),
      db.from("eventos").select("id", { count: "exact", head: true }).eq("tipo", "visita").gte("creado", desde7),
      db.from("eventos").select("id", { count: "exact", head: true }).eq("tipo", "whatsapp").gte("creado", desde7),
      db.from("resenas").select("*").eq("aprobada", false),
      db.from("reservas").select("total").eq("estado", "confirmada").gte("creada", desde7),
    ]);
    const vendido = (ingresos.data || []).reduce((a, r) => a + (r.total || 0), 0);
    const lista = (semana.data || []).map((r) => `<li><b>${lindo(r.entrada)}</b> · ${esc(cab(r.cabana_id))} · ${esc(r.nombre || "")} ${r.origen !== "web" ? `(${r.origen})` : ""}</li>`).join("");
    hecho.resumen = await enviarEmail(aj?.email_avisos || "", "📊 Tu semana en Aromas de Campo", plantilla("Resumen de la semana", `
      <p>🚗 <b>Llegan esta semana:</b></p>${lista ? `<ul>${lista}</ul>` : "<p>Ninguna llegada confirmada.</p>"}
      <p>🟠 <b>Pedidos esperando seña:</b> ${pend.data?.length || 0}</p>
      <p>💰 <b>Reservas confirmadas en los últimos 7 días:</b> ${pesos(vendido)}</p>
      <p>👀 <b>Visitas a la web:</b> ${visitas.count || 0} · <b>clics a WhatsApp:</b> ${wa.count || 0}</p>
      ${res.data?.length ? `<p>⭐ <b>${res.data.length} reseña(s) esperando tu aprobación.</b></p>` : ""}
      ${boton(web + "/admin.html", "Abrir el panel")}`));
  }

  return new Response(JSON.stringify({ ok: true, ...hecho }), { headers: { "Content-Type": "application/json" } });
});
