// supabase/functions/acceso/index.ts · Portal de Delegados 2028 (fase 75)
// Acceso al portal por función de servidor:
//   1. (opcional) verifica el captcha de Turnstile con la clave secreta;
//   2. verifica el PIN y cuenta los intentos en la base (portal_acceso_verificar);
//   3. si todo está bien, crea la sesión con un enlace de un solo uso y la devuelve.
// El gancho «Customize Access Token» niega cualquier sesión que no venga por aquí.
//
// Secretos necesarios (Edge Functions → Secrets): SUPABASE_URL y
// SUPABASE_SERVICE_ROLE_KEY (automáticos), SUPABASE_ANON_KEY (automático),
// EMAIL_DOM (opcional, por defecto @strategosfp.com), TURNSTILE_SECRET (opcional).
import { createClient } from "npm:@supabase/supabase-js@2";

const URL      = Deno.env.get("SUPABASE_URL")!;
const SERVICE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON     = Deno.env.get("SUPABASE_ANON_KEY")!;
const DOM      = Deno.env.get("EMAIL_DOM") || "@strategosfp.com";
const TS_SECRET = Deno.env.get("TURNSTILE_SECRET") || "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const emailDe = (acc: string) => {
  const a = String(acc || "").trim();
  if (a.includes("@")) return a.toLowerCase();
  return a.replace(/\D/g, "") + DOM;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, msg: "Método no permitido" }, 405);

  let body: { acceso?: string; pin?: string; captcha?: string } = {};
  try { body = await req.json(); } catch { return json({ ok: false, msg: "Solicitud inválida" }, 400); }
  const email = emailDe(body.acceso || "");
  const pin = String(body.pin || "");
  if (!email || email.startsWith("@") || !pin) return json({ ok: false, msg: "Escribe tu cédula y tu PIN." }, 400);

  const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1. Captcha: solo si hay clave secreta configurada Y la Comisión lo activó (sin clave, se ahorra la consulta)
  const cfg = TS_SECRET ? (await admin.schema("public").rpc("portal_config_publica")).data : null;
  if (cfg?.captcha_activo && TS_SECRET) {
    if (!body.captcha) return json({ ok: false, msg: "Completa la verificación de seguridad." }, 400);
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: TS_SECRET, response: body.captcha,
        remoteip: req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || undefined }),
    }).then((x) => x.json()).catch(() => ({ success: false }));
    if (!r?.success) return json({ ok: false, msg: "La verificación de seguridad falló. Inténtalo de nuevo." }, 400);
  }

  // 2. PIN e intentos, en la base
  const { data: v, error: ve } = await admin.schema("public").rpc("portal_acceso_verificar", { p_email: email, p_pin: pin });
  if (ve) return json({ ok: false, msg: "No se pudo verificar el acceso: " + ve.message }, 500);
  if (!v?.ok) return json({ ok: false, msg: v?.msg || "Cédula o PIN incorrectos." }, 401);

  // 3. Sesión: enlace de un solo uso canjeado aquí mismo
  const { data: link, error: le } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (le || !link?.properties?.hashed_token) return json({ ok: false, msg: "No se pudo crear la sesión." }, 500);
  const anon = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: s, error: se } = await anon.auth.verifyOtp({ token_hash: link.properties.hashed_token, type: "magiclink" });
  if (se || !s?.session) return json({ ok: false, msg: "No se pudo abrir la sesión: " + (se?.message || "") }, 500);

  return json({ ok: true, access_token: s.session.access_token, refresh_token: s.session.refresh_token });
});
