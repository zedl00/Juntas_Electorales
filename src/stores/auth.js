/* src/stores/auth.js */
import { ref, computed } from 'vue';
import { sb, EMAIL_DOM } from '../lib/supabase';
import { rolLbl } from '../lib/constantes';
import { soloDig } from '../lib/formato';
import { t } from './toasts';

export const sesion = ref(null);
export const perfil = ref(null);
export const showPin = ref(false);   // primer ingreso: obliga a crear PIN personal

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
  const { data, error } = await sb.rpc('portal_mi_perfil');
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
  showPin.value = !!p.primer_acceso;
  return true;
}

/** Inicia sesión con cédula (o email de admin) + PIN. Devuelve mensaje de error o null. */
export async function login(acceso, pin, captchaToken = '') {
  const { data, error } = await sb.auth.signInWithPassword({
    email: emailDe(acceso), password: pin,
    ...(captchaToken ? { options: { captchaToken } } : {})
  });
  if (error) {
    if (/invalid login/i.test(error.message)) return 'Cédula o PIN incorrectos.';
    if (/captcha/i.test(error.message)) return 'Supabase exige la verificación de seguridad pero el portal la tiene desactivada. Administración: actívala en Gestión → Usuarios → Seguridad del acceso.';
    return 'No se pudo iniciar sesión: ' + error.message;
  }
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
