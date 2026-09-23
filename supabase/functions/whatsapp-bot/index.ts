// ================================================================
//  PORTAL DE DELEGADOS 2028 · BOT DE WHATSAPP (Meta Cloud API)
//  Consultas de avance por territorio · sin nombres ni cédulas.
//  Desplegar:  supabase functions deploy whatsapp-bot --no-verify-jwt
//  Secretos:   WA_TOKEN · WA_PHONE_ID · WA_VERIFY_TOKEN
// ================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN     = Deno.env.get("WA_TOKEN")!;          // token permanente de la app de Meta
const PHONE_ID  = Deno.env.get("WA_PHONE_ID")!;       // id del número emisor
const VERIFY    = Deno.env.get("WA_VERIFY_TOKEN")!;   // cadena que tú eliges para el webhook
const GRAPH     = `https://graph.facebook.com/v21.0/${PHONE_ID}/messages`;

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { db: { schema: "delegados" } }
);

const fmt = (n: unknown) => Number(n ?? 0).toLocaleString("es-DO");
const pct = (t: unknown, m: unknown) => (Number(m) ? Math.round(Number(t) * 100 / Number(m)) : 0);
const barra = (p: number) => "▰".repeat(Math.round(p / 10)) + "▱".repeat(10 - Math.round(p / 10));

async function responder(to: string, texto: string) {
  const r = await fetch(GRAPH, {
    method: "POST",
    headers: { "Authorization": `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to, type: "text", text: { body: texto } }),
  });
  const cuerpo = await r.text();
  console.log(`[ENVIO] a=${to} estado=${r.status} respuesta=${cuerpo.slice(0, 400)}`);
  return r.ok;
}

const AYUDA =
  "🗳️ *Portal de Delegados FP 2028*\n_Consulta de avance por territorio_\n\n" +
  "Escribe una de estas opciones:\n\n" +
  "▸ *avance* — resumen nacional y por regiones\n" +
  "▸ *region Sur*\n" +
  "▸ *provincia San Juan*\n" +
  "▸ *municipio San Juan de la Maguana* — incluye sus distritos\n\n" +
  "_Este canal entrega solo cifras de avance. Nunca nombres, cédulas ni datos personales._";

const lineaTerr = (x: { nombre?: string; region?: string; meta: number; total: number }) =>
  `▸ *${x.nombre ?? x.region}*: ${fmt(x.total)} / ${fmt(x.meta)} (${pct(x.total, x.meta)}%)`;

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // ── Verificación del webhook (Meta la llama una sola vez con GET) ──
  if (req.method === "GET") {
    if (url.searchParams.get("hub.verify_token") === VERIFY) {
      return new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 });
    }
    return new Response("forbidden", { status: 403 });
  }

  try {
    const body = await req.json();
    console.log("[ENTRADA] " + JSON.stringify(body).slice(0, 600));
    const msg = body?.entry?.[0]?.changes?.[0]?.value?.messages?.[0];
    if (!msg) { console.log("[AVISO] Sin mensaje (probablemente un estado de entrega)"); return new Response("ok"); }
    if (msg.type !== "text") { console.log("[AVISO] Mensaje no textual: " + msg.type); return new Response("ok"); }
    console.log(`[CONFIG] token=${TOKEN ? TOKEN.length + ' caracteres' : 'AUSENTE'} phone_id=${PHONE_ID || 'AUSENTE'}`);

    const de: string = msg.from;                       // número del remitente, sin +
    const texto: string = (msg.text?.body ?? "").trim();
    const bajo = texto.toLowerCase();

    // ── Autorización: solo números registrados por la Comisión ──
    console.log(`[MENSAJE] de=${de} texto="${texto}"`);
    const { data: auth, error: authErr } = await sb.rpc("portal_bot_wa_auth", { p_tel: de, p_comando: texto.slice(0, 80) });
    if (authErr) console.log("[ERROR BD] " + authErr.message);
    console.log("[AUTORIZACION] " + JSON.stringify(auth));
    if (!auth?.ok) {
      await responder(de,
        "🔒 Este número no está autorizado.\n\n" +
        `Comparte este número — *${de}* — con la Comisión de Juntas Electorales y OCLEE para que te habiliten el acceso.`);
      return new Response("ok");
    }

    const cmd = bajo.split(/\s+/)[0];
    const arg = texto.split(/\s+/).slice(1).join(" ").trim();

    if (["avance", "nacional", "resumen"].includes(cmd)) {
      const { data } = await sb.rpc("portal_bot_resumen", { p_cedula: auth.cedula ?? null });
      if (!data) { await responder(de, "No pude consultar el avance. Intenta de nuevo."); return new Response("ok"); }
      const p = pct(data.total, data.meta);
      let out = `*${data.alcance ?? "Avance nacional"}* · Colegios 2028\n\n${barra(p)}  *${p}%*\n` +
        `Registrados: *${fmt(data.total)}* de *${fmt(data.meta)}*\n` +
        `Colegios: ${fmt(data.colegios)} · ✓ ${fmt(data.completos)} completos · ${fmt(data.parciales)} incompletos · ${fmt(data.vacios)} sin registro\n\n*Detalle:*\n`;
      for (const r of (data.regiones ?? data.municipios ?? [])) out += lineaTerr(r) + "\n";
      await responder(de, out);

    } else if (["region", "región", "provincia", "municipio"].includes(cmd)) {
      if (!arg) { await responder(de, `Escribe el nombre. Ejemplo: *${cmd} ${cmd.startsWith("reg") ? "Sur" : "San Juan"}*`); return new Response("ok"); }
      const nivel = cmd.startsWith("reg") ? "region" : cmd;
      const { data } = await sb.rpc("portal_bot_nivel", { p_nivel: nivel, p_clave: arg, p_cedula: auth.cedula ?? null });
      if (!data || data.error) { await responder(de, data?.error ?? "No encontré ese territorio. Verifica el nombre."); return new Response("ok"); }
      const p = pct(data.total, data.meta);
      let out = `📍 *${data.nombre}*` + (data.provincia ? ` · ${data.provincia}` : "") + (data.region ? ` · ${data.region}` : "") +
        `\n\n${barra(p)}  *${p}%*\nRegistrados: *${fmt(data.total)}* de *${fmt(data.meta)}*\n`;
      if (data.cobertura) out += `Colegios: ✓ ${fmt(data.cobertura.completos)} completos · ${fmt(data.cobertura.parciales)} incompletos · ${fmt(data.cobertura.vacios)} sin registro\n`;
      const hijos = data.hijos ?? data.distritos;
      if (hijos?.length) {
        out += `\n*${data.distritos ? "Distritos" : nivel === "region" ? "Provincias" : "Municipios"}:*\n`;
        for (const h of hijos) out += lineaTerr(h) + (h.es_dm ? " _· DM_" : "") + "\n";
      }
      await responder(de, out);

    } else if (cmd === "pin") {
      if (auth.rol !== "admin") { await responder(de, "⛔ El restablecimiento de PIN es solo para números de administración."); return new Response("ok"); }
      const ced = arg.replace(/\D/g, "");
      if (ced.length < 8) { await responder(de, "Uso: *pin 00112345678* (la cédula del usuario)."); return new Response("ok"); }
      const nuevo = String(Math.floor(100000 + Math.random() * 900000));
      const { data } = await sb.rpc("portal_bot_reset_pin", { p_cedula: ced, p_pin: nuevo });
      if (!data?.ok) { await responder(de, "No se pudo: " + (data?.error ?? "error desconocido")); return new Response("ok"); }
      await responder(de, `✅ PIN restablecido para *${data.nombre}*.\n\n▸ Cédula: ${ced}\n▸ PIN provisional: *${nuevo}*\n\nAl entrar deberá crear su PIN personal. Envíaselo y borra este mensaje.`);

    } else {
      await responder(de, AYUDA);
    }
    return new Response("ok");
  } catch (e) {
    console.log("[EXCEPCION] " + (e instanceof Error ? e.message : String(e)));
    return new Response("ok");   // Meta reintenta si no recibe 200
  }
});
