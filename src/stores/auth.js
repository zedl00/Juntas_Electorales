/* src/stores/auth.js */
import { ref, computed } from 'vue';
import { sb, EMAIL_DOM } from '../lib/supabase';
import { rolLbl } from '../lib/constantes';
import { soloDig } from '../lib/formato';
import { t } from './toasts';
import { comprobarVersion } from './actualizacion';

export const sesion = ref(null);
export const perfil = ref(null);
export const showPin = ref(false);   // primer ingreso: obliga a crear PIN personal
export const showIdent = ref(false); // primer ingreso: verificación de identidad contra el padrón (fase 74)

/* ── Derivados de perfil ── */
export const esAdmin = computed(() => perfil.value?.rol === 'admin_sne');
export const scopeAmplio = computed(() => ['admin_sne','supervisor_provincial','coordinador_regional','consulta_nacional'].includes(perfil.value?.rol));
export const esNacional = computed(() => ['admin_sne','consulta_nacional'].includes(perfil.value?.rol));
export const canRegister = computed(() => perfil.value?.puede_registrar === true
  || (perfil.value?.puede_registrar == null && ['enc_electoral','admin_sne'].includes(perfil.value?.rol)));
export const verDistritos = computed(() => perfil.value?.ver_distritos !== false);
/* Listados de personas: solo la administración o quien tenga el parámetro «Ver postulantes» (fase 82) */
export const vePostulantes = computed(() => perfil.value?.rol === 'admin_sne' || perfil.value?.ver_postulantes === true);

/* Permisos del rol: qué datos se ven y qué documentos se imprimen */
export const permisos = ref({
  ver_nombres: true, ver_cedula: false, ver_telefono: false,
  imprimir_individual: false, imprimir_relacion: false, imprimir_validacion: false
});

export async function cargarPermisos() {
  const { data } = await sb.rpc('portal_mis_permisos');
  if (data) permisos.value = data;
}

/* Texto para la marca de agua de pantalla */
export const velo = computed(() => {
  const n = perfil.value?.nombre || '';
  const h = new Date().toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' });
  return `${n}\n${h}`;
});
export const iniciales = computed(() => (perfil.value?.nombre || '?').split(/\s+/).slice(0, 2).map(p => p[0]).join('').toUpperCase());
export const ribbon = computed(() => {
  const p = perfil.value || {};
  if (p.rol === 'admin_sne') return { titulo: 'Seguimiento Nacional', sub: 'Secretaría Nacional Electoral · Comisión de Juntas Electorales y OCLEE' };
  if (p.rol === 'coordinador_regional') return { titulo: 'Región ' + (p.region || '—'), sub: rolLbl[p.rol] };
  if (p.rol === 'supervisor_provincial') return { titulo: 'Provincia ' + (p.provincia || '—'), sub: rolLbl[p.rol] };
  if (p.distrito) return {
    titulo: p.distrito,
    sub: (p.municipio ? p.municipio + ' · ' : '') + (p.provincia ? p.provincia + ' · ' : '') + (rolLbl[p.rol] || '')
  };
  return { titulo: p.municipio || '—', sub: (p.provincia ? p.provincia + ' · ' : '') + (rolLbl[p.rol] || '') };
});

/* ── Sesión ── */
const emailDe = acc => acc.includes('@') ? acc.trim().toLowerCase() : (soloDig(acc) + EMAIL_DOM);

async function cargarPerfil() {
  const { data, error } = await sb.rpc('portal_mi_perfil', { p_agente: typeof navigator !== 'undefined' ? navigator.userAgent : null });
  if (error) { t('Error cargando tu perfil', 'err'); return null; }
  perfil.value = data;
  return data;
}

/** Carga el perfil tras autenticar. Devuelve true si el acceso es válido. */
export async function postLogin() {
  /* Fase 88: antes de mostrar nada, si la última actividad guardada supera el límite, la sesión se cierra aquí mismo */
  await cargarLimiteInactividad();
  if (inactividadMin > 0 && minutosInactivo() >= inactividadMin) { await cerrarPorInactividad(); return false; }
  const [p] = await Promise.all([cargarPerfil(), cargarPermisos()]);   // en paralelo: ahorra un viaje al servidor
  if (!p) { t('Tu cuenta no tiene perfil en el Portal de Delegados. Contacta a la Comisión.', 'err'); await sb.auth.signOut(); sesion.value = null; return false; }
  if (!p.activo) { t('Tu acceso está desactivado. Contacta a la Comisión.', 'err'); await sb.auth.signOut(); sesion.value = null; perfil.value = null; return false; }
  showIdent.value = !!p.verificar_identidad && p.rol !== 'admin_sne';   // primero identidad, después el PIN personal; la administración nunca
  showPin.value = !!p.primer_acceso;
  iniciarLatido();
  return true;
}

/** Verificación de identidad contra el padrón (fase 74). Devuelve mensaje de error o null. */
export async function verificarIdentidad(fechaNac, municipioId) {
  const { data, error } = await sb.rpc('portal_verificar_identidad', { p_fecha_nac: fechaNac, p_municipio_id: municipioId || null });
  if (error) return 'No se pudo verificar: ' + error.message;
  if (data?.ok) { showIdent.value = false; if (perfil.value) perfil.value.verificar_identidad = false; return null; }
  if (data?.bloqueado) { t(data.msg, 'err'); await sb.auth.signOut(); setTimeout(() => location.reload(), 2500); return data.msg; }
  return data?.msg || 'Los datos no coinciden.';
}

/** Inicia sesión con cédula (o email de admin) + PIN. Devuelve mensaje de error o null. */
export async function login(acceso, pin, captchaToken = '') {
  /* Fase 75: el acceso pasa por la función de servidor «acceso», que verifica el PIN,
     cuenta los intentos con las reglas de la Comisión y crea la sesión. */
  let r;
  try {
    const resp = await fetch(import.meta.env.VITE_SUPABASE_URL + '/functions/v1/acceso', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': import.meta.env.VITE_SUPABASE_ANON_KEY,
                 'Authorization': 'Bearer ' + import.meta.env.VITE_SUPABASE_ANON_KEY },
      body: JSON.stringify({ acceso, pin, captcha: captchaToken || undefined })
    });
    r = await resp.json().catch(() => ({}));
    if (!resp.ok || !r?.ok) return r?.msg || 'No se pudo iniciar sesión (' + resp.status + ').';
  } catch (e) {
    return 'No hay conexión con el servidor de acceso. Revisa tu internet e inténtalo de nuevo.';
  }
  const { data, error } = await sb.auth.setSession({ access_token: r.access_token, refresh_token: r.refresh_token });
  if (error || !data?.session) return 'No se pudo abrir la sesión: ' + (error?.message || '');
  marcarActividad();                                   // entrar cuenta como actividad
  sesion.value = data.session;
  const ok = await postLogin();
  return ok ? null : 'Acceso no habilitado.';
}

export async function logout() {
  detenerLatido();
  try { await sb.rpc('portal_salir'); } catch (e) { /* sin conexión: la sesión vence sola */ }
  try { await sb.auth.signOut(); } finally { location.reload(); }
}

/* ── Cierre por inactividad (fase 88) ──
   La última actividad se guarda en el navegador para que sobreviva a recargas y a días con la pestaña abierta.
   La app se cierra sola al superar el límite (aunque no haya conexión); la base lo confirma en cada latido. */
const ACT_KEY = 'portal_act';
let inactividadMin = 0, actTimer = null, versionMinima = '';
let ultimaActividadMem = Date.now();
function marcarActividad() {
  ultimaActividadMem = Date.now();
  try { localStorage.setItem(ACT_KEY, String(ultimaActividadMem)); } catch (e) { /* sin almacenamiento */ }
}
function minutosInactivo() {
  let t = ultimaActividadMem;
  try { const g = parseInt(localStorage.getItem(ACT_KEY) || '', 10); if (Number.isFinite(g)) t = Math.min(t, g); } catch (e) { /* sin almacenamiento */ }
  return (Date.now() - t) / 60000;
}
async function cargarLimiteInactividad() {
  try {
    const { data } = await sb.schema('public').rpc('portal_config_publica');
    inactividadMin = Math.max(0, +(data?.inactividad_minutos ?? 0) || 0);
    versionMinima = data?.version_minima || '';
  } catch (e) { /* conserva el valor anterior */ }
}
async function cerrarPorInactividad() {
  detenerLatido();
  const msg = 'Tu sesión se cerró por inactividad: más de ' + inactividadMin + ' minutos sin usar el portal. Vuelve a entrar con tu PIN.';
  try { sessionStorage.setItem('portal_aviso', msg); } catch (e) { /* sin almacenamiento */ }
  try { await sb.rpc('portal_salir'); } catch (e) { /* sin conexión */ }
  try { await sb.auth.signOut(); } finally { location.reload(); }
}
const EVENTOS_ACT = ['pointerdown', 'keydown', 'scroll', 'touchstart'];
let actThrottle = 0;
function alActuar() { const n = Date.now(); if (n - actThrottle > 5000) { actThrottle = n; marcarActividad(); } }
function vigilarInactividad() {
  dejarDeVigilar();
  EVENTOS_ACT.forEach(ev => document.addEventListener(ev, alActuar, { passive: true }));
  actTimer = setInterval(() => { if (sesion.value && inactividadMin > 0 && minutosInactivo() >= inactividadMin) cerrarPorInactividad(); }, 30000);
}
function dejarDeVigilar() {
  EVENTOS_ACT.forEach(ev => document.removeEventListener(ev, alActuar));
  if (actTimer) clearInterval(actTimer);
  actTimer = null;
}

/* ── Sesión única (fase 86): latido cada 2 minutos y al volver a primer plano ──
   La base responde «cerrada» cuando otra persona entró con el mismo usuario o la Comisión cerró la sesión. */
const LATIDO_MS = 120000;
let latidoTimer = null, latidoEnCurso = false;
async function latido() {
  if (!sesion.value || latidoEnCurso) return;
  latidoEnCurso = true;
  try {
    const { data, error } = await sb.rpc('portal_latido', { p_inactivo_min: Math.floor(minutosInactivo()) });
    if (error || !data) return;                                   // sin conexión o sin respuesta: no se cierra nada
    if (data.estado === 'cerrada') {
      detenerLatido();
      if (data.motivo === 'inactividad') { try { localStorage.removeItem(ACT_KEY); } catch (e) { /* sin almacenamiento */ } }
      try { sessionStorage.setItem('portal_aviso', data.msg || 'Tu sesión fue cerrada.'); } catch (e) { /* sin almacenamiento */ }
      t(data.msg || 'Tu sesión fue cerrada.', 'err');
      try { await sb.auth.signOut(); } finally { setTimeout(() => location.reload(), 1500); }
    }
  } finally { latidoEnCurso = false; }
}
function latidoVisible() {
  if (document.visibilityState !== 'visible') return;
  cargarLimiteInactividad().then(() => comprobarVersion(versionMinima));
  if (sesion.value && inactividadMin > 0 && minutosInactivo() >= inactividadMin) { cerrarPorInactividad(); return; }   // volver a la pestaña no cuenta como actividad
  latido();
}
function iniciarLatido() {
  detenerLatido();
  vigilarInactividad();
  latido();
  latidoTimer = setInterval(latido, LATIDO_MS);
  document.addEventListener('visibilitychange', latidoVisible);
}
function detenerLatido() {
  dejarDeVigilar();
  if (latidoTimer) clearInterval(latidoTimer);
  latidoTimer = null;
  document.removeEventListener('visibilitychange', latidoVisible);
}

/* ── Arranque: restaurar sesión antes de montar el router ── */
let readyResolve;
export const authReady = new Promise(r => { readyResolve = r; });

export async function inicializarAuth() {
  await cargarLimiteInactividad();
  if (await comprobarVersion(versionMinima)) return;      // versión vieja: se recarga, no sigue
  sb.auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT') { detenerLatido(); sesion.value = null; perfil.value = null; } });
  const { data } = await sb.auth.getSession();
  if (data?.session) { sesion.value = data.session; await postLogin(); }
  readyResolve();
}

/* ── PIN ── */
export async function guardarPin(nuevo) {
  const { error } = await sb.auth.updateUser({ password: nuevo });
  if (error) return 'No se pudo guardar: ' + error.message;
  await sb.rpc('portal_pin_cambiado');
  if (perfil.value) perfil.value.primer_acceso = false;
  showPin.value = false;
  return null;
}

/* ── Acuse de lectura del Instructivo ── */
export async function registrarAcuse() {
  const { data, error } = await sb.rpc('portal_acuse_instructivo');
  if (error) { t('No se pudo registrar el acuse', 'err'); return; }
  if (perfil.value) perfil.value.acuse_instructivo = data;
  t('Acuse de lectura registrado', 'ok');
}
