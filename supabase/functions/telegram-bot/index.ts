// ================================================================
//  PORTAL DE DELEGADOS 2028 · BOT DE TELEGRAM (Supabase Edge Function)
//  Consultas de avance por territorio (sin nombres) + reset de PIN.
//  Desplegar con:  supabase functions deploy telegram-bot --no-verify-jwt
//  Requiere el secreto TELEGRAM_TOKEN (ver docs/GUIA_BOT.md).
// ================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = Deno.env.get("TELEGRAM_TOKEN")!;
const API = `https://api.telegram.org/bot${TOKEN}`;

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { db: { schema: "delegados" } }
);

const fmt = (n: unknown) => Number(n ?? 0).toLocaleString("es-DO");
const pct = (t: unknown, m: unknown) => (Number(m) ? Math.round(Number(t) * 100 / Number(m)) : 0);
const barra = (p: number) => "▰".repeat(Math.round(p / 10)) + "▱".repeat(10 - Math.round(p / 10));

async function enviar(chatId: number, texto: string) {
  await fetch(`${API}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text: texto, parse_mode: "Markdown" }),
  });
}

const AYUDA =
  "🗳️ *Portal de Delegados FP 2028 · Bot de seguimiento*\n\n" +
  "Comandos disponibles:\n" +
  "▸ /avance — resumen nacional y por regiones\n" +
  "▸ /region Gran Santo Domingo\n" +
  "▸ /provincia Santiago\n" +
  "▸ /municipio Los Alcarrizos — con sus distritos\n" +
  "▸ /id — tu identificador de chat (para autorización)\n" +
  "_Solo se muestran avances y metas. Nunca nombres ni datos personales._";

function lineaTerr(x: { nombre?: string; region?: string; provincia_nombre?: string; meta: number; total: number }) {
  const p = pct(x.total, x.meta);
  return `▸ *${x.nombre ?? x.region}*: ${fmt(x.total)} / ${fmt(x.meta)} (${p}%)`;
}

Deno.serve(async (req) => {
  try {
    const update = await req.json();
    const msg = update.message ?? update.edited_message;
    if (!msg?.text) return new Response("ok");
    const chatId: number = msg.chat.id;
    const texto: string = msg.text.trim();
    const [cmdRaw, ...resto] = texto.split(/\s+/);
    const cmd = cmdRaw.toLowerCase().replace(/@.*$/, "");
    const arg = resto.join(" ").trim();

    if (cmd === "/id") {
      await enviar(chatId, `Tu identificador de chat es: \`${chatId}\`\nCompártelo con la Comisión para que autorice tu acceso.`);
      return new Response("ok");
    }

    // ── Autorización: solo chats registrados por la Comisión ──
    const { data: auth } = await sb.rpc("portal_bot_tg_auth", { p_chat: chatId, p_comando: texto.slice(0, 80) });
    if (!auth?.ok) {
      await enviar(chatId,
        "🔒 Este chat no está autorizado.\n\nEnvía /id, comparte el número con la Comisión de Juntas Electorales y OCLEE, y te habilitarán en un minuto.");
      return new Response("ok");
    }

    if (cmd === "/start" || cmd === "/ayuda" || cmd === "/help") {
      await enviar(chatId, AYUDA);

    } else if (cmd === "/avance") {
      const { data, error } = await sb.rpc("portal_bot_resumen", { p_cedula: auth.cedula ?? null });
      if (error || !data) { await enviar(chatId, "No pude consultar el avance. Intenta de nuevo."); return new Response("ok"); }
      const p = pct(data.total, data.meta);
      let out = `*${data.alcance ?? "Avance nacional"}* · Colegios 2028\n\n` +
        `${barra(p)}  *${p}%*\n` +
        `Registrados: *${fmt(data.total)}* de *${fmt(data.meta)}*\n` +
        `Colegios: ${fmt(data.colegios)} · ✓ ${fmt(data.completos)} completos · ${fmt(data.parciales)} incompletos · ${fmt(data.vacios)} sin registro\n\n*Detalle:*\n`;
      for (const r of (data.regiones ?? data.municipios ?? [])) out += lineaTerr(r) + "\n";
      await enviar(chatId, out);

    } else if (cmd === "/region" || cmd === "/provincia" || cmd === "/municipio") {
      if (!arg) { await enviar(chatId, `Escribe el nombre. Ejemplo: \`${cmd} ${cmd === "/region" ? "Este" : cmd === "/provincia" ? "Santiago" : "Los Alcarrizos"}\``); return new Response("ok"); }
      const { data, error } = await sb.rpc("portal_bot_nivel", { p_nivel: cmd.slice(1), p_clave: arg, p_cedula: auth.cedula ?? null });
      if (error || !data || data.error) { await enviar(chatId, data?.error ?? "No encontré ese territorio."); return new Response("ok"); }
      const p = pct(data.total, data.meta);
      let out = `📍 *${data.nombre}*` +
        (data.provincia ? ` · ${data.provincia}` : "") + (data.region ? ` · ${data.region}` : "") + `\n\n` +
        `${barra(p)}  *${p}%*\nRegistrados: *${fmt(data.total)}* de *${fmt(data.meta)}*\n`;
      if (data.cobertura) out += `Colegios: ✓ ${fmt(data.cobertura.completos)} completos · ${fmt(data.cobertura.parciales)} incompletos · ${fmt(data.cobertura.vacios)} sin registro\n`;
      const hijos = data.hijos ?? data.distritos;
      if (hijos?.length) {
        out += `\n*${data.distritos ? "Distritos" : data.nivel === "region" ? "Provincias" : "Municipios"}:*\n`;
        for (const h of hijos) out += lineaTerr(h) + (h.es_dm ? " _· DM_" : "") + "\n";
      }
      await enviar(chatId, out);

    } else if (cmd === "/pin") {
      if (auth.rol !== "admin") { await enviar(chatId, "⛔ El restablecimiento de PIN es solo para chats de administración."); return new Response("ok"); }
      const ced = arg.replace(/\D/g, "");
      if (ced.length < 8) { await enviar(chatId, "Uso: `/pin 00112345678` (la cédula del usuario)."); return new Response("ok"); }
      const pin = String(Math.floor(100000 + Math.random() * 900000));
      const { data, error } = await sb.rpc("portal_bot_reset_pin", { p_cedula: ced, p_pin: pin });
      if (error || !data?.ok) { await enviar(chatId, "No se pudo: " + (data?.error ?? error?.message ?? "error desconocido")); return new Response("ok"); }
      await enviar(chatId,
        `✅ PIN restablecido para *${data.nombre}*.\n\n▸ Cédula: ${ced}\n▸ PIN provisional: *${pin}*\n\nAl entrar deberá crear su PIN personal. Envíaselo por WhatsApp y bórralo de este chat.`);

    } else {
      await enviar(chatId, AYUDA);
    }
    return new Response("ok");
  } catch (_e) {
    return new Response("ok");
  }
});
