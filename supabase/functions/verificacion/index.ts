// supabase/functions/verificacion/index.ts · Portal de Delegados 2028 (fase 85)
// API de verificación de membresía para la Secretaría de Organización.
//   GET  /verificacion/pendientes?limite=200   arma y entrega un lote de cédulas pendientes
//   GET  /verificacion/lotes/{id}              vuelve a entregar un lote ya creado, con su estado actual
//   POST /verificacion/resultados              recibe [{cedula, estado, nota?}] y los guarda
// Autenticación: cabecera «Authorization: Bearer <clave>» (o «x-api-key»). La clave la emite
// Gestión → Verificación de miembros; se guarda cifrada y se puede revocar.
// Desplegar SIN verificación de JWT de Supabase, porque la clave es propia:
//   supabase functions deploy verificacion --no-verify-jwt
// Secretos: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (automáticos).
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });
const db = () => admin.schema("delegados");

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-api-key, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });
const fallo = (status: number, codigo: string, mensaje: string, extra: Record<string, unknown> = {}) =>
  json({ ok: false, error: { codigo, mensaje, ...extra } }, status);

const ESTADOS = ["miembro", "no_miembro", "no_localizado", "en_revision"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const ruta = url.pathname.replace(/^.*\/verificacion/, "").replace(/\/+$/, "") || "/";
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "";
  const agente = req.headers.get("user-agent") || "";
  const endpoint = req.method + " " + ruta;

  // ── Autenticación por clave propia ──
  const auth = req.headers.get("authorization") || "";
  const clave = (auth.toLowerCase().startsWith("bearer ") ? auth.slice(7) : req.headers.get("x-api-key") || "").trim();
  const log = (cliente: { id?: number; nombre?: string } | null, rec: number, ok: number, rech: number, resultado: string, detalle: unknown = null) =>
    db().rpc("portal_api_log", { p_cliente_id: cliente?.id ?? null, p_cliente: cliente?.nombre ?? null, p_endpoint: endpoint, p_ip: ip, p_agente: agente,
      p_recibidos: rec, p_aceptados: ok, p_rechazados: rech, p_resultado: resultado, p_detalle: detalle });

  if (!clave) { await log(null, 0, 0, 0, "sin_clave"); return fallo(401, "sin_clave", "Falta la clave: cabecera Authorization: Bearer <clave>"); }
  const { data: cli, error: eCli } = await db().rpc("portal_api_cliente_validar", { p_clave: clave });
  if (eCli || !cli) { await log(null, 0, 0, 0, "clave_invalida"); return fallo(401, "clave_invalida", "Clave no válida o revocada"); }
  const ips: string[] = Array.isArray(cli.ip_permitidas) ? cli.ip_permitidas : [];
  if (ips.length && !ips.includes(ip)) { await log(cli, 0, 0, 0, "ip_no_permitida", { ip }); return fallo(403, "ip_no_permitida", "Dirección no autorizada para este consumidor"); }

  try {
    // ── GET /pendientes ──
    if (req.method === "GET" && ruta === "/pendientes") {
      const pedido = parseInt(url.searchParams.get("limite") || "", 10);
      const limite = Number.isFinite(pedido) && pedido > 0 ? Math.min(pedido, cli.limite_lote || pedido) : (cli.limite_lote || null);
      const { data, error } = await db().rpc("portal_verif_lote_crear", { p_via: "api", p_limite: limite, p_cliente_id: cli.id });
      if (error) throw error;
      await log(cli, 0, data?.cantidad ?? 0, 0, "ok", { lote: data?.lote });
      return json({ ok: true, lote: data.lote, creado_en: data.creado_en, cantidad: data.cantidad, registros: data.registros,
        mensaje: data.cantidad ? undefined : "No hay cédulas pendientes de verificación" });
    }
    // ── GET /lotes/{id} ──
    const mLote = ruta.match(/^\/lotes\/(\d+)$/);
    if (req.method === "GET" && mLote) {
      const { data, error } = await db().rpc("portal_verif_lote_obtener", { p_lote: parseInt(mLote[1], 10) });
      if (error) throw error;
      if (!data) { await log(cli, 0, 0, 0, "lote_inexistente", { lote: mLote[1] }); return fallo(404, "lote_inexistente", "Ese lote no existe"); }
      await log(cli, 0, data.cantidad ?? 0, 0, "ok", { lote: data.lote });
      return json({ ok: true, ...data });
    }
    // ── POST /resultados ──
    if (req.method === "POST" && ruta === "/resultados") {
      let body: { lote?: number; resultados?: unknown } = {};
      try { body = await req.json(); } catch { await log(cli, 0, 0, 0, "json_invalido"); return fallo(400, "json_invalido", "El cuerpo debe ser JSON"); }
      const items = Array.isArray(body.resultados) ? body.resultados : null;
      if (!items) { await log(cli, 0, 0, 0, "formato_invalido"); return fallo(400, "formato_invalido", "Se espera {\"resultados\": [{\"cedula\": \"...\", \"estado\": \"...\"}]}"); }
      if (items.length === 0) return fallo(400, "lista_vacia", "La lista de resultados está vacía");
      if (items.length > 1000) { await log(cli, items.length, 0, 0, "exceso"); return fallo(413, "exceso", "Máximo 1000 resultados por llamada"); }
      const { data, error } = await db().rpc("portal_verif_resultados", { p_items: items, p_fuente: "api", p_cliente_id: cli.id, p_lote: body.lote ?? null });
      if (error) throw error;
      const rech = Array.isArray(data?.rechazados) ? data.rechazados : [];
      await log(cli, items.length, data?.aceptados ?? 0, rech.length, rech.length && !data?.aceptados ? "rechazado" : "ok", { lote: body.lote ?? null, rechazados: rech.slice(0, 50) });
      return json({ ok: true, recibidos: items.length, aceptados: data.aceptados, rechazados: rech, lotes: data.lotes, estados_validos: ESTADOS });
    }
    await log(cli, 0, 0, 0, "ruta_desconocida");
    return fallo(404, "ruta_desconocida", "Rutas: GET /pendientes, GET /lotes/{id}, POST /resultados");
  } catch (e) {
    const msg = (e as Error)?.message || String(e);
    await log(cli, 0, 0, 0, "error", { msg });
    return fallo(500, "error", msg);
  }
});
