// Aromas de Campo — avisa por email cada reserva nueva que entra por la web.
// La dispara la base de datos (trigger "aromas_avisar"). Envía con Resend (gratis hasta 3.000 emails/mes).
// Secretos necesarios en Supabase → Edge Functions → Secrets:  RESEND_API_KEY
// (SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya vienen incluidos)
import { createClient } from "jsr:@supabase/supabase-js@2";

const fmt = (n: number) => "$" + new Intl.NumberFormat("es-AR").format(Math.round(n || 0));
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const DIAS = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
const lindo = (s: string) => { const [y, m, d] = s.split("-").map(Number); const f = new Date(Date.UTC(y, m - 1, d)); return `${DIAS[f.getUTCDay()]} ${d} ${MESES[m - 1]}`; };
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

Deno.serve(async (req) => {
  try {
    const { id } = await req.json();
    if (!Number.isInteger(id)) return new Response("id inválido", { status: 400 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    // Solo reservas recién creadas y todavía no avisadas: así nadie puede usar esta función para mandar spam
    const { data: r } = await db.from("reservas").select("*, cabanas(nombre)")
      .eq("id", id).eq("notificada", false).eq("origen", "web")
      .gte("creada", new Date(Date.now() - 10 * 60 * 1000).toISOString()).maybeSingle();
    if (!r) return new Response("nada para avisar", { status: 200 });
    await db.from("reservas").update({ notificada: true }).eq("id", id);

    const { data: aj } = await db.from("ajustes").select("email_avisos").single();
    const para = aj?.email_avisos;
    const key = Deno.env.get("RESEND_API_KEY");
    if (!para || !key) return new Response("falta email o RESEND_API_KEY", { status: 200 });

    const noches = (Date.parse(r.salida) - Date.parse(r.entrada)) / 86400000;
    let tel = String(r.telefono || "").replace(/\D/g, "").replace(/^0/, "");
    if (!tel.startsWith("54")) tel = "549" + tel.replace(/^15/, "");
    const panel = (Deno.env.get("PANEL_URL") || "https://aromasdecampo.vercel.app/admin.html");
    const html = `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#1E1E1E">
        <h2 style="color:#4F6049">🌿 Nueva reserva desde la web</h2>
        <p style="font-size:16px"><b>${esc(r.nombre)}</b> pidió la cabaña <b>${esc(r.cabanas?.nombre)}</b></p>
        <table style="font-size:15px;border-collapse:collapse;width:100%">
          <tr><td style="padding:6px 0;color:#666">Llega</td><td><b>${lindo(r.entrada)}</b></td></tr>
          <tr><td style="padding:6px 0;color:#666">Se va</td><td><b>${lindo(r.salida)}</b> (${noches} noches)</td></tr>
          <tr><td style="padding:6px 0;color:#666">Personas</td><td>${r.personas}${r.mascota ? " · con mascota 🐾" : ""}</td></tr>
          <tr><td style="padding:6px 0;color:#666">Total</td><td><b>${fmt(r.total)}</b> · seña ${fmt(r.sena)}</td></tr>
          <tr><td style="padding:6px 0;color:#666">Teléfono</td><td>${esc(r.telefono)}</td></tr>
          ${r.email ? `<tr><td style="padding:6px 0;color:#666">Email</td><td>${esc(r.email)}</td></tr>` : ""}
          <tr><td style="padding:6px 0;color:#666">Código</td><td>${esc(r.codigo)}</td></tr>
        </table>
        ${r.mensaje ? `<p style="background:#F0EBE1;padding:10px;border-radius:8px">💬 ${esc(r.mensaje)}</p>` : ""}
        <p>Ojo: hasta que no pague la seña <b>las fechas siguen libres</b> para otros. Cuando te llegue la seña, confirmala en el panel con un toque.</p>
        <p><a href="https://wa.me/${tel}" style="background:#25D366;color:#fff;padding:12px 18px;border-radius:10px;text-decoration:none;font-weight:bold">Escribirle por WhatsApp</a>
           &nbsp; <a href="${panel}" style="background:#7A8C72;color:#fff;padding:12px 18px;border-radius:10px;text-decoration:none;font-weight:bold">Abrir el panel</a></p>
      </div>`;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: Deno.env.get("EMAIL_DESDE") || "Aromas de Campo <onboarding@resend.dev>",
        to: para.split(",").map((x: string) => x.trim()).filter(Boolean),
        subject: `🌿 Nueva reserva: ${r.nombre} · ${r.cabanas?.nombre} · ${lindo(r.entrada)}`,
        html,
      }),
    });
    return new Response(res.ok ? "enviado" : "error resend: " + await res.text(), { status: 200 });
  } catch (e) {
    return new Response("error: " + (e as Error).message, { status: 200 });
  }
});
