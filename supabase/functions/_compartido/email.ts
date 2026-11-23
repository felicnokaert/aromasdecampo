// Envío de emails con Resend (gratis hasta 3.000 por mes)
// RESEND_API_KEY: obligatorio. EMAIL_DESDE: remitente con dominio verificado (ej: "Aromas de Campo <reservas@aromasdecampo.com.ar>").
// Sin dominio verificado, Resend solo deja mandar al email del dueño de la cuenta → solo avisos internos.
export const puedeEscribirHuespedes = () => !!Deno.env.get("EMAIL_DESDE") && !!Deno.env.get("RESEND_API_KEY");

export async function enviarEmail(para: string | string[], asunto: string, html: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return false;
  const to = (Array.isArray(para) ? para : String(para).split(",")).map((x) => x.trim()).filter(Boolean);
  if (!to.length) return false;
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: Deno.env.get("EMAIL_DESDE") || "Aromas de Campo <onboarding@resend.dev>", to, subject: asunto, html }),
  });
  if (!r.ok) console.error("Resend:", await r.text());
  return r.ok;
}

export const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
export const pesos = (n: number) => "$" + new Intl.NumberFormat("es-AR").format(Math.round(n || 0));
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
export const lindo = (s: string) => { const [y, m, d] = s.split("-").map(Number); const f = new Date(Date.UTC(y, m - 1, d)); return `${DIAS[f.getUTCDay()]} ${d} de ${MESES[m - 1]}`; };
export const hoyAR = (masDias = 0) => { const d = new Date(Date.now() - 3 * 3600e3); d.setUTCDate(d.getUTCDate() + masDias); return d.toISOString().slice(0, 10); };

export const plantilla = (titulo: string, cuerpo: string) => `
  <div style="background:#F2EADB;padding:24px 12px;font-family:Arial,sans-serif;color:#1E1E1E">
    <div style="max-width:540px;margin:auto;background:#fff;border-radius:16px;overflow:hidden">
      <div style="background:#24301F;color:#F2EADB;padding:18px 22px;font-size:20px;font-family:Georgia,serif">Aromas de Campo</div>
      <div style="padding:22px;font-size:15px;line-height:1.55">
        <h2 style="margin:0 0 12px;color:#24301F;font-family:Georgia,serif">${titulo}</h2>${cuerpo}
      </div>
      <div style="padding:14px 22px;background:#F0EBE1;color:#6B6B6B;font-size:12px">Cabañas de tronco · Colón, Entre Ríos</div>
    </div>
  </div>`;
export const boton = (url: string, txt: string, color = "#D2662A") =>
  `<a href="${url}" style="display:inline-block;background:${color};color:#fff;padding:12px 18px;border-radius:999px;text-decoration:none;font-weight:bold;margin:6px 6px 0 0">${txt}</a>`;
