// supabase/functions/cuentas/index.ts · Portal de Delegados 2028 (fase 91)
// Crea la cuenta de acceso (auth.users) de un usuario nuevo desde el servidor, con el rol de
// servicio, para poder CERRAR el registro público de cuentas en Supabase Auth.
// Solo la llama Gestión → Usuarios → Nuevo usuario. Exige la sesión de un admin_sne.
//   POST /cuentas  { cedula, pin }  →  { ok, id }
// Desplegar CON verificación de JWT (por defecto):  supabase functions deploy cuentas
// Secretos: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (automáticos), EMAIL_DOM (opcional).
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DOM = Deno.env.get("EMAIL_DOM") || "@strategosfp.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, msg: "Método no permitido" }, 405);

  // 1. ¿Quién llama? Debe ser una sesión válida de un administrador
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return json({ ok: false, msg: "Sesión requerida" }, 401);
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: { user }, error: ue } = await asUser.auth.getUser();
  if (ue || !user) return json({ ok: false, msg: "Sesión no válida" }, 401);

  const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: quien } = await admin.schema("delegados").from("usuarios_territoriales").select("rol, nombre, activo").eq("id", user.id).maybeSingle();
  if (!quien || quien.rol !== "admin_sne" || !quien.activo) {
    await admin.schema("delegados").from("eventos_sistema").insert({ usuario_id: user.id, accion: "cuenta_denegada", entidad: "usuario", entidad_id: null,
      detalle: { motivo: "no es administrador", ip: req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") } });
    return json({ ok: false, msg: "Solo la administración de la SNE puede crear cuentas" }, 403);
  }

  // 2. Datos
  let body: { cedula?: string; pin?: string } = {};
  try { body = await req.json(); } catch { return json({ ok: false, msg: "Solicitud inválida" }, 400); }
  const ced = String(body.cedula || "").replace(/\D/g, "");
  const pin = String(body.pin || "");
  if (ced.length < 8 || ced.length > 11) return json({ ok: false, msg: "Cédula incompleta" }, 400);
  if (pin.length < 6 || pin.length > 72) return json({ ok: false, msg: "El PIN debe tener al menos 6 caracteres" }, 400);

  // 3. Crear la cuenta con el rol de servicio (no pasa por el registro público)
  const email = ced + DOM;
  const { data, error } = await admin.auth.admin.createUser({ email, password: pin, email_confirm: true });
  if (error) {
    const dup = /already|registered|exists/i.test(error.message);
    return json({ ok: false, msg: dup ? "Esta cédula ya tiene una cuenta de acceso creada." : "No se pudo crear la cuenta: " + error.message }, dup ? 409 : 500);
  }
  await admin.schema("delegados").from("eventos_sistema").insert({ usuario_id: user.id, accion: "cuenta_creada", entidad: "usuario", entidad_id: ced,
    detalle: { por: quien.nombre, ip: req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") } });
  return json({ ok: true, id: data.user?.id });
});
