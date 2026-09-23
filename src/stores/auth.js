/* src/stores/auth.js */
import { ref, computed } from 'vue';
import { sb, EMAIL_DOM } from '../lib/supabase';
import { rolLbl } from '../lib/constantes';
import { soloDig } from '../lib/formato';
import { t } from './toasts';

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
  const p = await cargarPerfil();
  if (p) await cargarPermisos();
  if (!p) { t('Tu cuenta no tiene perfil en el Portal de Delegados. Contacta a la Comisión.', 'err'); await sb.auth.signOut(); sesion.value = null; return false; }
  if (!p.activo) { t('Tu acceso está desactivado. Contacta a la Comisión.', 'err'); await sb.auth.signOut(); sesion.value = null; perfil.value = null; return false; }
  showIdent.value = !!p.verificar_identidad;   // primero identidad, después el PIN personal
  showPin.value = !!p.primer_acceso;
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
  sesion.value = data.session;
  const ok = await postLogin();
  return ok ? null : 'Acceso no habilitado.';
}

export async function logout() {
  try { await sb.auth.signOut(); } finally { location.reload(); }
}

/* ── Arranque: restaurar sesión antes de montar el router ── */
let readyResolve;
export const authReady = new Promise(r => { readyResolve = r; });

export async function inicializarAuth() {
  sb.auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT') { sesion.value = null; perfil.value = null; } });
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
