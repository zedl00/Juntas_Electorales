<!-- src/views/UsuariosView.vue -->
<script setup>
import { RouterLink, useRoute, useRouter } from 'vue-router';
import { ref, computed, onMounted, watch } from 'vue';
import { sb, sbAux, EMAIL_DOM, PORTAL_URL } from '../lib/supabase';
import { perfil, esAdmin } from '../stores/auth';
import { catMap, catGrupos, provsOf, regiones } from '../stores/catalogo';
import { rolLbl, alcanceLbl } from '../lib/constantes';
import { fmt, fmtCed, fmtTel, soloDig, fecha, fechaHora, genPin, waLink } from '../lib/formato';
import { t, copiar } from '../stores/toasts';
import { cargarDocsCfg } from '../stores/print';

const permRol = ref([]), permBusy = ref(false);
const usrs = ref([]), uBusy = ref(false), uF = ref({ q: '', rol: '', prov: '', mun: '', jce: '', ambito: '', estado: '' });
const showCrear = ref(false), cuBusy = ref(false), cuErr = ref(''), cuPend = ref(null), cuOk = ref(null);
const cu = ref({ ced: '', lkpU: null, nombre: '', telefono: '', rol: 'enc_electoral', mun: 0, prov: 0, region: '', pin: genPin(), puedeImp: null });

/* ── Avance por territorio de cada usuario (fase 68): colegios · meta · registrados ── */
const kpiU = ref(new Map());
const cargarKpiU = async () => {
  const { data } = await sb.rpc('portal_kpi_usuarios');
  kpiU.value = new Map((data || []).map(r => [r.municipio_id + ':' + (r.jce_id ?? ''), r]));
};
const sumaFilas = filas => filas.reduce((a, r) => ({ colegios: a.colegios + +r.colegios, meta: a.meta + +r.meta, total: a.total + +r.total }), { colegios: 0, meta: 0, total: 0 });
const avance = u => {
  if (!kpiU.value.size) return null;
  let r = null;
  if (u.jce_id && u.municipio_id)      r = kpiU.value.get(u.municipio_id + ':' + u.jce_id);
  else if (u.municipio_id)             r = kpiU.value.get(u.municipio_id + ':');
  else if (u.provincia_id)             r = sumaFilas([...kpiU.value.values()].filter(x => x.jce_id == null && catMap.value.get(x.municipio_id)?.provincia_id === u.provincia_id));
  else if (u.region)                   r = sumaFilas([...kpiU.value.values()].filter(x => x.jce_id == null && catMap.value.get(x.municipio_id)?.macroregion === u.region));
  if (!r) return null;
  const meta = +r.meta || 0, total = +r.total || 0;
  return { colegios: +r.colegios || 0, meta, total, pct: meta ? Math.min(100, Math.round(total * 100 / meta)) : 0 };
};

const cargarUsrs = async () => {
  if (!esAdmin.value) return;
  uBusy.value = true;
  /* Supabase devuelve 1,000 filas por consulta: se pide por tramos hasta agotar */
  const todos = [];
  let desde = 0; const paso = 1000; let error = null;
  for (let i = 0; i < 20; i++) {
    const r = await sb.from('usuarios_territoriales').select('*')
      .order('created_at', { ascending: false }).range(desde, desde + paso - 1);
    if (r.error) { error = r.error; break; }
    todos.push(...(r.data || []));
    if ((r.data || []).length < paso) break;
    desde += paso;
  }
  const data = todos;
  const dd = await sb.from('portal_distritos').select('jce_id,nombre');
  const mapD = new Map((dd.data || []).map(d => [d.jce_id, d.nombre]));
  if (data) data.forEach(u => { if (u.jce_id) u.distrito_nombre = mapD.get(u.jce_id); });
  uBusy.value = false;
  if (!error) usrs.value = data || [];
};

/* ── Orden por columna (clic en el título; segundo clic invierte) ── */
const uSort = ref({ c: 'nombre', asc: true });
const ordenarPor = c => { if (uSort.value.c === c) uSort.value.asc = !uSort.value.asc; else uSort.value = { c, asc: true }; };
const flecha = c => uSort.value.c === c ? (uSort.value.asc ? ' ▲' : ' ▼') : '';
const terrTexto = u => {
  const m = catMap.value.get(u.municipio_id);
  return [m?.provincia_nombre || (u.provincia_id ? String(u.provincia_id) : ''), m?.nombre || '', u.jce_id ? String(u.jce_id) : ''].join(' · ').toLowerCase();
};
const claveOrden = u => {
  switch (uSort.value.c) {
    case 'cedula':      return soloDig(u.cedula);
    case 'rol':         return (rolLbl[u.rol] || u.rol || '').toLowerCase();
    case 'territorio':  return terrTexto(u);
    case 'avance':      return avance(u)?.pct ?? -1;
    case 'acceso':      return u.ultimo_acceso || '';
    case 'instructivo': return u.acuse_instructivo ? 1 : 0;
    case 'estado':      return (u.activo ? 2 : 0) + (u.primer_acceso ? 0 : 1);
    default:            return String(u.nombre || '').toLowerCase();
  }
};
const usrsView = computed(() => usrsFiltrados.value.slice().sort((a, b) => {
  const x = claveOrden(a), y = claveOrden(b);
  const r = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y), 'es');
  return uSort.value.asc ? r : -r;
}));

const usrsFiltrados = computed(() => usrs.value.filter(u => {
  const q = uF.value.q.trim().toLowerCase();
  if (q && !(String(u.nombre || '').toLowerCase().includes(q) || soloDig(u.cedula).includes(soloDig(q)))) return false;
  if (uF.value.rol && u.rol !== uF.value.rol) return false;
  if (uF.value.prov) { const pid = u.provincia_id || catMap.value.get(u.municipio_id)?.provincia_id; if (pid !== uF.value.prov) return false; }
  if (uF.value.mun && u.municipio_id !== uF.value.mun) return false;
  if (uF.value.jce && u.jce_id !== uF.value.jce) return false;
  if (uF.value.ambito) {
    const a = u.jce_id ? 'distrito' : (u.municipio_id ? 'municipio' : (u.provincia_id ? 'provincia' : 'nacional'));
    if (a !== uF.value.ambito) return false;
  }
  if (uF.value.estado === 'activos' && !u.activo) return false;
  if (uF.value.estado === 'inactivos' && u.activo) return false;
  return true;
}));

/* ── Edición de usuario ── */
const ed = ref(null), edBusy = ref(false), edErr = ref(''), edDists = ref([]), edCircs = ref([]);

const abrirEdicion = async u => {
  edErr.value = '';
  ed.value = {
    id: u.id, cedula: u.cedula,
    nombre: u.nombre || '', telefono: u.telefono || '',
    rol: u.rol, mun: u.municipio_id || 0, jce: u.jce_id || 0,
    ambito: (!u.municipio_id && u.provincia_id) ? 'provincia' : 'municipio',
    circ: u.circ_codigo || '',
    prov: u.provincia_id || 0, region: u.region || '',
    verD: u.ver_distritos !== false,
    puedeImp: u.puede_imprimir,
    forzar: !!u.primer_acceso,
    puedeReg: u.puede_registrar,
    activo: !!u.activo
  };
  edDists.value = []; edCircs.value = [];
  if (u.municipio_id) {
    const { data: cc } = await sb.from('portal_circ_municipio')
      .select('circ_codigo,circ_nombre').eq('municipio_id', u.municipio_id).order('circ_codigo');
    edCircs.value = cc || [];
    const { data } = await sb.from('portal_distritos')
      .select('jce_id,nombre,es_dm,colegios').eq('municipio_id', u.municipio_id).order('es_dm').order('nombre');
    edDists.value = data || [];
  }
};

const edCargarDists = async id => {
  edDists.value = []; edCircs.value = []; ed.value.jce = 0; ed.value.circ = '';
  if (!id) return;
  const { data: cc } = await sb.from('portal_circ_municipio')
    .select('circ_codigo,circ_nombre').eq('municipio_id', id).order('circ_codigo');
  edCircs.value = cc || [];
  const { data } = await sb.from('portal_distritos')
    .select('jce_id,nombre,es_dm,colegios').eq('municipio_id', id).order('es_dm').order('nombre');
  edDists.value = data || [];
};

const resetDesdeEdicion = async () => {
  const e = ed.value;
  ed.value = null;
  await resetPin({ id: e.id, cedula: e.cedula, nombre: e.nombre, rol: e.rol,
                   telefono: e.telefono, municipio_id: e.mun, jce_id: e.jce,
                   provincia_id: e.prov, region: e.region });
};

const guardarEdicion = async () => {
  const e = ed.value;
  if (!e.nombre.trim()) { edErr.value = 'El nombre es obligatorio.'; return; }
  const cargo = ['presidente','secretario_general','enc_electoral'].includes(e.rol);
  const municipal = cargo && e.ambito !== 'provincia';
  const provincial = cargo && e.ambito === 'provincia';
  if (municipal && !e.mun) { edErr.value = 'Elige el municipio.'; return; }
  if (provincial && !e.prov) { edErr.value = 'Elige la provincia.'; return; }
  if (e.rol === 'supervisor_provincial' && !e.prov) { edErr.value = 'Elige la provincia.'; return; }
  if (e.rol === 'coordinador_regional' && !e.region) { edErr.value = 'Elige la región.'; return; }
  edBusy.value = true; edErr.value = '';
  const { error } = await sb.from('usuarios_territoriales').update({
    nombre: e.nombre.trim(),
    telefono: e.telefono.trim() || null,
    rol: e.rol,
    municipio_id: municipal ? e.mun : null,
    jce_id: municipal && e.jce ? e.jce : null,
    circ_codigo: e.circ || null,
    provincia_id: (provincial || e.rol === 'supervisor_provincial') ? e.prov : null,
    region: e.rol === 'coordinador_regional' ? e.region : null,
    ver_distritos: e.verD !== false,
    puede_imprimir: cu.value.puedeImp === false ? false : null,
    puede_imprimir: e.puedeImp === false ? false : null,
    primer_acceso: !!e.forzar,
    puede_registrar: e.puedeReg === true ? true : false,
    activo: e.activo
  }).eq('id', e.id);
  edBusy.value = false;
  if (error) { edErr.value = error.message; return; }
  t('Usuario actualizado', 'ok');
  ed.value = null;
  cargarUsrs();
};

/* ── Consultas por WhatsApp ── */
const wa = ref([]), waOpen = ref(false), waBusy = ref(false), waErr = ref('');
const waF = ref({ tel: '', desc: '', ced: '', rol: 'consulta' });

/* Qué puede hacer cada usuario, resumido para el listado */
/* Valor efectivo del permiso de registro en el formulario de edición */
const regEfectivo = (e) => {
  if (!e) return false;
  if (e.puedeReg === true) return true;
  if (e.puedeReg === false) return false;
  return e.rol === 'enc_electoral' && e.ambito !== 'provincia';
};

const capacidad = (u) => {
  const registra = u.puede_registrar === true
    || (u.puede_registrar == null && ['enc_electoral','admin_sne'].includes(u.rol));
  const imprime  = u.puede_imprimir !== false;
  const partes = ['Consulta'];
  if (registra) partes.unshift('Registra postulantes');
  if (imprime)  partes.push('imprime');
  return { digita: registra, imprime, ayuda: partes.join(' · ') };
};

/* fmtTel viene de lib/formato: misma máscara 809-000-0000 en pantalla y al escribir */
const waNorm = t => { const d = soloDig(t || ''); return d.length === 10 ? '1' + d : d; };
const waPretty = t => {
  const d = String(t || '');
  return d.length === 11 ? `+${d[0]} (${d.slice(1,4)}) ${d.slice(4,7)}-${d.slice(7)}` : '+' + d;
};

const cargarWa = async () => {
  const { data, error } = await sb.rpc('portal_bot_wa_lista');
  if (error) {
    waErr.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase23_admin_whatsapp.sql en Supabase: los números se guardan pero no pueden listarse.'
      : 'No se pudo leer la lista: ' + error.message;
    return;
  }
  wa.value = data || [];
};

const guardarWa = async () => {
  const tel = waNorm(waF.value.tel);
  if (tel.length < 11) { waErr.value = 'Escribe el número completo con área, por ejemplo 809 555 1234.'; return; }
  if (!waF.value.desc.trim()) { waErr.value = 'Escribe a quién pertenece el número.'; return; }
  waBusy.value = true; waErr.value = '';
  const { error } = await sb.rpc('portal_bot_wa_alta', {
    p_tel: tel, p_cedula: waF.value.ced || null,
    p_desc: waF.value.desc.trim(), p_rol: waF.value.rol
  });
  waBusy.value = false;
  if (error) { waErr.value = error.message; return; }
  t('Número autorizado: ' + waPretty(tel), 'ok');
  waF.value = { tel: '', desc: '', ced: '', rol: 'consulta' };
  await cargarWa();
  if (!wa.value.some(w => w.telefono === tel) && !waErr.value) {
    waErr.value = 'El número se guardó, pero no aparece en la lista. Recarga la página.';
  }
};

const waEstado = async (w) => {
  const { error } = await sb.rpc('portal_bot_wa_estado', { p_tel: w.telefono, p_activo: !w.activo });
  if (error) { t(error.message, 'err'); return; }
  t(w.activo ? 'Acceso revocado' : 'Acceso reactivado', 'ok');
  cargarWa();
};

const waBaja = async (w) => {
  if (!confirm('¿Eliminar por completo el acceso de ' + (w.descripcion || w.telefono) + '?')) return;
  const { error } = await sb.rpc('portal_bot_wa_baja', { p_tel: w.telefono });
  if (error) { t(error.message, 'err'); return; }
  t('Acceso eliminado', 'ok');
  cargarWa();
};

/* ── Consultas por Telegram ── */
const canal = ref('whatsapp');
const tg = ref([]), tgBusy = ref(false), tgErr = ref('');
const tgF = ref({ chat: '', desc: '', ced: '', rol: 'consulta' });

/* Usuarios del portal disponibles para enlazar con el asistente */
const usrsEnlazables = computed(() => usrs.value.filter(u => u.activo));
const nombreDeCedula = c => {
  const u = usrs.value.find(x => soloDig(x.cedula) === soloDig(c || ''));
  return u ? u.nombre : null;
};
const alElegirUsrWa = () => {
  const u = usrs.value.find(x => x.cedula === waF.value.ced);
  if (u) waF.value.desc = u.nombre + ' · ' + (rolLbl[u.rol] || u.rol);
};
const alElegirUsrTg = () => {
  const u = usrs.value.find(x => x.cedula === tgF.value.ced);
  if (u) tgF.value.desc = u.nombre + ' · ' + (rolLbl[u.rol] || u.rol);
};

const cargarTg = async () => {
  const { data, error } = await sb.rpc('portal_bot_tg_lista');
  if (error) {
    tgErr.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase26_admin_telegram.sql en Supabase.'
      : 'No se pudo leer la lista: ' + error.message;
    return;
  }
  tg.value = data || [];
};

const guardarTg = async () => {
  const chat = Number(String(tgF.value.chat).replace(/[^0-9-]/g, ''));
  if (!chat) { tgErr.value = 'Pega el identificador que la persona recibe al escribir /id al asistente.'; return; }
  if (!tgF.value.desc.trim()) { tgErr.value = 'Escribe a quién pertenece el acceso.'; return; }
  tgBusy.value = true; tgErr.value = '';
  const { error } = await sb.rpc('portal_bot_tg_alta', {
    p_chat: chat, p_cedula: tgF.value.ced || null,
    p_desc: tgF.value.desc.trim(), p_rol: tgF.value.rol
  });
  tgBusy.value = false;
  if (error) { tgErr.value = error.message; return; }
  t('Acceso autorizado', 'ok');
  tgF.value = { chat: '', desc: '', ced: '', rol: 'consulta' };
  cargarTg();
};

const tgEstado = async (w) => {
  const { error } = await sb.rpc('portal_bot_tg_estado', { p_chat: w.chat_id, p_activo: !w.activo });
  if (error) { t(error.message, 'err'); return; }
  t(w.activo ? 'Acceso revocado' : 'Acceso reactivado', 'ok');
  cargarTg();
};

const tgBaja = async (w) => {
  if (!confirm('¿Eliminar por completo el acceso de ' + (w.descripcion || w.chat_id) + '?')) return;
  const { error } = await sb.rpc('portal_bot_tg_baja', { p_chat: w.chat_id });
  if (error) { t(error.message, 'err'); return; }
  t('Acceso eliminado', 'ok');
  cargarTg();
};

const solis = ref([]);
/* ── Bandejas de seguridad (fase 74): bloqueados · por confirmar · accesos por enviar ── */
const bloqueados = ref([]), porConfirmar = ref([]), pinesEnviar = ref([]), segAccion = ref('');
const cargarBandejas = async () => {
  const [b, c, e] = await Promise.all([
    sb.rpc('portal_bloqueados'), sb.rpc('portal_accesos_por_confirmar'), sb.rpc('portal_pines_por_enviar')
  ]);
  bloqueados.value = b.data || []; porConfirmar.value = c.data || []; pinesEnviar.value = e.data || [];
};
const desbloquear = async b => {
  segAccion.value = b.id;
  const { data, error } = await sb.rpc('portal_desbloquear', { p_id: b.id });
  segAccion.value = '';
  if (error || !data?.ok) { t('No se pudo habilitar: ' + (error?.message || data?.msg), 'err'); return; }
  t(b.nombre + ' habilitado(a)', 'ok'); cargarBandejas(); cargarUsrs();
};
const confirmarAcceso = async (c, ok) => {
  const nota = ok ? null : (prompt('Motivo (opcional) para desactivar el acceso de ' + c.nombre + ':') || null);
  if (!ok && nota === null && !confirm('¿Desactivar el acceso de ' + c.nombre + '?')) return;
  segAccion.value = c.id;
  const { data, error } = await sb.rpc('portal_confirmar_acceso', { p_id: c.id, p_ok: ok, p_nota: nota });
  segAccion.value = '';
  if (error || !data?.ok) { t('No se pudo: ' + (error?.message || data?.msg), 'err'); return; }
  t(ok ? 'Identidad confirmada: ' + c.nombre : 'Acceso desactivado: ' + c.nombre, 'ok'); cargarBandejas(); cargarUsrs();
};
/* Enviar siguiente: abre WhatsApp con el mensaje de acceso y marca el PIN como entregado */
const enviarPin = async r => {
  if (r.vencido) { t('Ese PIN venció: regenera uno nuevo con «↺ PIN nuevo» en la lista de usuarios.', 'err'); return; }
  if (!r.telefono) { t('Esa persona no tiene teléfono registrado.', 'err'); return; }
  window.open(waLink(r.telefono, accessMsg(r.nombre, r.rol, r.territorio || '', fmtCed(r.cedula), r.pin)), '_blank');
  const { error } = await sb.rpc('portal_pin_entregado', { p_cedula: r.cedula });
  if (error) { t('Enviado, pero no se pudo marcar: ' + error.message, 'err'); return; }
  t('Marcado como enviado: ' + r.nombre, 'ok'); cargarBandejas();
};
const enviarSiguiente = () => { const r = pinesEnviar.value.find(x => !x.vencido && x.telefono); if (r) enviarPin(r); else t('No queda nadie por enviar.', 'ok'); };

const cargarSolis = async () => {
  const { data } = await sb.rpc('portal_solicitudes_pin');
  solis.value = data || [];
};

const munsFiltro = computed(() => {
  const l = [...catMap.value.values()].filter(m => !uF.value.prov || m.provincia_id === uF.value.prov);
  return l.sort((a, b) => String(a.nombre).localeCompare(String(b.nombre)));
});
const distsFiltro = ref([]);
watch(() => uF.value.mun, async id => {
  distsFiltro.value = []; uF.value.jce = '';
  if (!id) return;
  const { data } = await sb.from('portal_distritos').select('jce_id,nombre,es_dm')
    .eq('municipio_id', id).order('es_dm').order('nombre');
  distsFiltro.value = data || [];
});
watch(() => uF.value.prov, () => { uF.value.mun = ''; uF.value.jce = ''; });

const distsU = ref([]);
const cargarDistsU = async id => {
  distsU.value = [];
  if (cu.value) cu.value.jce = 0;
  if (!id) return;
  const { data } = await sb.from('portal_distritos').select('jce_id,nombre,es_dm,colegios').eq('municipio_id', id).order('es_dm').order('nombre');
  distsU.value = data || [];
};

const territorioDe = u => {
  if (u.rol === 'consulta_nacional') return 'Nacional · consulta';
  if (u.jce_id && u.distrito_nombre) return u.distrito_nombre + ' (distrito)';
  if (u.municipio_id) { const m = catMap.value.get(u.municipio_id); return (m?.nombre || 'Mun. ' + u.municipio_id) + (m?.provincia_nombre ? ' · ' + m.provincia_nombre : ''); }
  if (u.provincia_id && !u.municipio_id) { const p = provsOf('').find(x => x.id === u.provincia_id); return 'Provincia ' + (p?.nombre || u.provincia_id); }
  if (u.rol === 'coordinador_regional' && u.region) return 'Región ' + u.region;
  return 'Nacional';
};

const toggleActivo = async u => {
  if (u.id === perfil.value?.id) { t('No puedes desactivar tu propia cuenta: quedarías fuera del portal.', 'err'); return; }
  const { error } = await sb.from('usuarios_territoriales').update({ activo: !u.activo }).eq('id', u.id);
  if (error) { t('No se pudo cambiar el estado', 'err'); return; }
  u.activo = !u.activo;
};

const accessMsg = (nombre, rolK, terrTxt, cedTxt, pin) => (
  '🗳️ *Portal de Delegados FP 2028*\nSecretaría Nacional Electoral\n\n' +
  'Hola ' + nombre + ', se te ha creado acceso como *' + (rolLbl[rolK] || rolK) + '* de *' + terrTxt + '*.\n\n' +
  '▸ Enlace: ' + PORTAL_URL + '\n' +
  '▸ Usuario (cédula): ' + cedTxt + '\n' +
  (pin ? '▸ PIN inicial: ' + pin + '\n' : '▸ PIN: el mismo que ya usas. Si no lo recuerdas, responde este mensaje y la Comisión te genera uno nuevo en un minuto.\n') +
  '\nEn tu primer ingreso el sistema te pedirá crear tu PIN personal. Desde el navegador puedes instalar la app en tu teléfono.\n\n' +
  '_Acceso personal e intransferible · Uso exclusivo institucional._'
);

const copiarAcceso = u => copiar(accessMsg(u.nombre, u.rol, territorioDe(u), fmtCed(u.cedula), null));
const waAcceso = u => {
  const ok = confirm(
    'Reenviar el acceso a ' + u.nombre + ' SIN PIN.\n\n' +
    'El PIN no se puede recuperar: está cifrado de forma irreversible.\n' +
    'Este mensaje solo lleva el enlace y la cédula, para quien ya conoce su PIN.\n\n' +
    'Si la persona olvidó su PIN, cancela y usa «↺ PIN nuevo».'
  );
  if (!ok) return;
  window.open(waLink(u.telefono, accessMsg(u.nombre, u.rol, territorioDe(u), fmtCed(u.cedula), null)), '_blank');
};

const resetPin = async u => {
  const pin = genPin();
  if (!confirm('¿Restablecer el PIN de ' + u.nombre + '?\n\nSe generará el PIN provisional ' + pin + ' y la persona deberá crear su PIN personal al entrar.')) return;
  const { error } = await sb.rpc('portal_reset_pin', { p_cedula: u.cedula, p_pin: String(pin) });
  if (error) { t('No se pudo restablecer: ' + error.message, 'err'); return; }
  t('PIN restablecido', 'ok');
  cargarSolis();
  cuOk.value = { reset: true, nombre: u.nombre, tel: u.telefono, pin: String(pin), msg: accessMsg(u.nombre, u.rol, territorioDe(u), fmtCed(u.cedula), String(pin)) };
  showCrear.value = true;
  cargarUsrs();
};

const abrirCrear = () => {
  cu.value = { ced: '', lkpU: null, nombre: '', telefono: '', rol: 'enc_electoral', mun: 0, jce: 0, prov: 0, region: '', verD: true, puedeReg: null, pin: genPin() };
  distsU.value = [];
  cuErr.value = ''; cuPend.value = null; cuOk.value = null; showCrear.value = true;
};

const buscarCedU = async () => {
  cu.value.lkpU = null;
  const d = soloDig(cu.value.ced);
  if (d.length < 8) { cuErr.value = 'Cédula incompleta.'; return; }
  cuErr.value = '';
  cuBusy.value = true;
  const { data, error } = await sb.rpc('portal_buscar_cedula', { p_ced: d });
  cuBusy.value = false;
  if (error) { cuErr.value = 'Error consultando el padrón: ' + error.message; return; }
  cu.value.lkpU = data;
  if (data?.encontrado && !cu.value.nombre) cu.value.nombre = (data.nombres + ' ' + data.apellido1 + ' ' + (data.apellido2 || '')).trim();
};

const terrDePayload = pl => {
  if (pl.municipio_id) return territorioDe({ municipio_id: pl.municipio_id });
  if (pl.rol === 'supervisor_provincial') return territorioDe({ rol: pl.rol, provincia_id: pl.provincia_id });
  if (pl.rol === 'coordinador_regional') return 'Región ' + pl.region;
  return 'Nacional';
};

const crearUsuario = async () => {
  cuErr.value = '';
  const ced = soloDig(cu.value.ced);
  const terrRol = ['presidente','secretario_general','enc_electoral'].includes(cu.value.rol);
  if (ced.length < 8) { cuErr.value = 'Cédula incompleta.'; return; }
  if (terrRol && !cu.value.mun) { cuErr.value = 'Selecciona el municipio del usuario.'; return; }
  if (cu.value.rol === 'supervisor_provincial' && !cu.value.prov) { cuErr.value = 'Selecciona la provincia.'; return; }
  if (cu.value.rol === 'coordinador_regional' && !cu.value.region) { cuErr.value = 'Selecciona la región.'; return; }
  if (String(cu.value.pin).length < 6) { cuErr.value = 'El PIN debe tener al menos 6 caracteres.'; return; }
  cuBusy.value = true;
  const { data: su, error: e1 } = await sbAux.auth.signUp({ email: ced + EMAIL_DOM, password: String(cu.value.pin) });
  if (e1) {
    cuBusy.value = false;
    cuErr.value = /already|registered|exists/i.test(e1.message)
      ? 'Esta cédula ya tiene una cuenta de acceso creada.'
      : (/email.*invalid|invalid.*email/i.test(e1.message)
          ? 'Supabase rechazó el dominio interno «' + EMAIL_DOM + '». Debe ser un dominio real. Cámbialo en el archivo .env (VITE_EMAIL_DOM) y vuelve a compilar.'
          : 'No se pudo crear la cuenta: ' + e1.message);
    return;
  }
  const uid = su?.user?.id;
  if (!uid) { cuBusy.value = false; cuErr.value = 'La cuenta no devolvió identificador. En Supabase → Authentication → Providers → Email, desactiva "Confirm email" y reintenta.'; return; }
  const m = catMap.value.get(cu.value.mun);
  const payload = {
    id: uid, cedula: ced, nombre: cu.value.nombre.trim(), telefono: cu.value.telefono.trim() || null,
    rol: cu.value.rol,
    municipio_id: terrRol ? cu.value.mun : null,
    ver_distritos: cu.value.verD !== false,
    puede_registrar: cu.value.puedeReg,
    jce_id: ['presidente','secretario_general','enc_electoral'].includes(cu.value.rol) && cu.value.jce ? cu.value.jce : null,
    provincia_id: cu.value.rol === 'supervisor_provincial' ? cu.value.prov : (terrRol ? (m?.provincia_id || null) : null),
    region: cu.value.rol === 'coordinador_regional' ? cu.value.region : (terrRol ? (m?.macroregion || null) : null),
    created_by: perfil.value.id
  };
  const { error: e2 } = await sb.from('usuarios_territoriales').insert(payload);
  cuBusy.value = false;
  if (e2) { cuPend.value = { payload }; t('La cuenta se creó pero el perfil falló: ' + e2.message, 'err'); return; }
  cuOk.value = { nombre: payload.nombre, tel: payload.telefono, pin: String(cu.value.pin), msg: accessMsg(payload.nombre, payload.rol, terrDePayload(payload), fmtCed(ced), String(cu.value.pin)) };
  cuPend.value = null; cargarUsrs();
};

const reintentarPerfil = async () => {
  if (!cuPend.value) return;
  cuBusy.value = true;
  const { error } = await sb.from('usuarios_territoriales').insert(cuPend.value.payload);
  cuBusy.value = false;
  if (error) { t('Sigue fallando: ' + error.message, 'err'); return; }
  const pl = cuPend.value.payload;
  cuOk.value = { nombre: pl.nombre, tel: pl.telefono, pin: String(cu.value.pin), msg: accessMsg(pl.nombre, pl.rol, terrDePayload(pl), fmtCed(pl.cedula), String(cu.value.pin)) };
  cuPend.value = null; cargarUsrs();
};

const irA = (id) => {
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

/* ── Pestañas: Usuarios · Asistente · Configuración (la pestaña viaja en ?t= para enlazar directo) ── */
const route = useRoute(); const router = useRouter();
const tab = ref(['usuarios','accesos','asistente','config'].includes(route.query.t) ? route.query.t : 'usuarios');
watch(tab, v => router.replace({ query: { ...route.query, t: v } }));
const tabs = [
  { k: 'usuarios',  txt: 'Usuarios' },
  { k: 'accesos',   txt: 'Accesos y seguridad' },
  { k: 'asistente', txt: 'Asistente de consulta' },
  { k: 'config',    txt: 'Configuración' }
];
/* Bandejas plegables de la pestaña Accesos: cada una se abre o cierra por separado */
const abre = ref({ solis: true, bloqueados: true, confirmar: true, enviar: false });
const pendAccesos = computed(() => solis.value.length + bloqueados.value.length + porConfirmar.value.length);
const irConfig = id => { tab.value = 'config'; setTimeout(() => irA(id), 60); };

/* ── Configuración de traslados ── */
const cfgTr = ref({ alcance: 'municipio', excede_accion: 'autorizar', encargado_solo_municipio: true, modo_asignacion: 'si_difiere' });
const cfgBusy = ref(false);

/* ── Seguridad del acceso: captcha de Cloudflare (fase 60) ── */
const cfgSeg = ref({ captcha_activo: false, captcha_site_key: '', bloqueo_activo: true, intentos_aviso: 3, intentos_bloqueo: 5, bloqueo_minutos: 15, verificar_padron: true, pin_caduca_horas: 72, confirmar_sne: true });
const segBusy = ref(false);
const cargarCfgSeg = async () => {
  const { data } = await sb.from('config_seguridad').select('*').limit(1).maybeSingle();
  if (data) cfgSeg.value = { ...data, captcha_site_key: data.captcha_site_key || '' };
};
const guardarCfgSeg = async () => {
  segBusy.value = true;
  const c = cfgSeg.value;
  const { error } = await sb.rpc('portal_config_seguridad_guardar', { p: {
    captcha_activo: !!c.captcha_activo, captcha_site_key: c.captcha_site_key || '',
    bloqueo_activo: !!c.bloqueo_activo, intentos_aviso: +c.intentos_aviso || 3, intentos_bloqueo: +c.intentos_bloqueo || 5,
    bloqueo_minutos: +c.bloqueo_minutos || 15, verificar_padron: !!c.verificar_padron,
    pin_caduca_horas: +c.pin_caduca_horas || 72, confirmar_sne: !!c.confirmar_sne
  } });
  segBusy.value = false;
  if (error) { t('No se pudo guardar: ' + error.message, 'err'); cargarCfgSeg(); return; }
  t('Seguridad del acceso guardada', 'ok');
  cargarCfgSeg();
};

/* ── Marca de agua por documento ── */
const cfgDoc = ref({});
const docs = [
  { k: 'sello_individual', t: 'Formulario individual',    d: 'Lleva los datos personales del postulante.' },
  { k: 'sello_blanco',     t: 'Formulario en blanco',     d: 'Sin datos. Pensado para fotocopiarse y repartir; la marca señalaría a quien imprimió el original, no a quien reparte.' },
  { k: 'sello_relacion',   t: 'Relación de postulantes',  d: 'Listado completo del territorio. El documento de mayor riesgo.' },
  { k: 'sello_validacion', t: 'Reporte para validación',  d: 'Colegios con sus personas, para la asamblea.' },
  { k: 'sello_resumen',    t: 'Formulario general',       d: 'Consolidado del territorio con las firmas de la dirigencia.' }
];

const cargarCfgDoc = async () => {
  const { data } = await sb.from('config_documentos').select('*').limit(1).maybeSingle();
  if (data) cfgDoc.value = data;
};

const guardarCfgDoc = async (campo, valor) => {
  const { error } = await sb.rpc('portal_config_documentos_set', { p_campo: campo, p_valor: valor });
  if (error) { t('No se pudo guardar: ' + error.message, 'err'); cargarCfgDoc(); return; }
  cfgDoc.value[campo] = valor;
  cargarDocsCfg();
  t('Configuración guardada', 'ok');
};

const cargarCfgTr = async () => {
  const { data } = await sb.from('config_traslados').select('*').limit(1).maybeSingle();
  if (data) cfgTr.value = {
    ...data,
    excede_accion: data.excede_accion || (data.requiere_autorizacion ? 'autorizar' : 'permitir'),
    encargado_solo_municipio: data.encargado_solo_municipio !== false
  };
};

const guardarCfgTr = async () => {
  cfgBusy.value = true;
  const { data, error } = await sb.rpc('portal_config_traslados_set', {
    p_alcance: cfgTr.value.alcance,
    p_excede: cfgTr.value.excede_accion,
    p_encargado_solo: cfgTr.value.encargado_solo_municipio
  });
  if (!error) {
    await sb.from('config_traslados').update({ modo_asignacion: cfgTr.value.modo_asignacion }).eq('id', true);
  }
  cfgBusy.value = false;
  if (error) { t('No se pudo guardar: ' + error.message, 'err'); cargarCfgTr(); return; }
  if (data?.ok) t('Configuración guardada', 'ok');
};

const cargarPermRol = async () => {
  const { data, error } = await sb.from('permisos_rol').select('*').order('rol');
  if (error) { t('Permisos: ' + error.message, 'err'); return; }
  permRol.value = data || [];
};

const guardarPermRol = async (r, campo, valor) => {
  permBusy.value = true;
  const { error } = await sb.from('permisos_rol')
    .update({ [campo]: valor, actualizado: new Date().toISOString() }).eq('rol', r.rol);
  permBusy.value = false;
  if (error) { t('No se pudo guardar: ' + error.message, 'err'); cargarPermRol(); return; }
  r[campo] = valor;
  t('Permiso actualizado', 'ok');
};

onMounted(() => { cargarBandejas(); cargarKpiU(); cargarCfgDoc(); cargarCfgTr(); cargarCfgSeg(); cargarPermRol(); cargarUsrs(); cargarSolis(); cargarWa(); cargarTg(); });
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <h2 class="font-serif text-xl font-bold mr-auto">Gestión</h2>
      <RouterLink to="/dirigencia" class="btn-o btn-s">⬡ Dirigencia territorial</RouterLink>
      <button v-if="tab === 'usuarios'" class="btn-p btn-s" @click="abrirCrear">+ Nuevo usuario</button>
    </div>

    <!-- Pestañas -->
    <div class="inline-flex rounded-xl bg-paper border border-line p-1 gap-1">
      <button v-for="tb in tabs" :key="tb.k" class="px-3.5 py-1.5 rounded-lg text-[13px] font-semibold transition-colors"
              :class="tab === tb.k ? 'bg-white shadow-sm text-ink' : 'text-mut hover:text-ink'" @click="tab = tb.k">
        {{ tb.txt }}
        <span v-if="tb.k === 'usuarios'" class="text-mut font-normal">· {{ usrs.length }}</span>
        <span v-else-if="tb.k === 'asistente'" class="text-mut font-normal">· {{ wa.filter(w => w.activo).length + tg.filter(w => w.activo).length }}</span>
        <span v-else-if="tb.k === 'accesos' && pendAccesos" class="badge border-amber-300 bg-amber-50 text-amber-800 !py-0 ml-1" title="Pendientes de atender">{{ pendAccesos }}</span>
      </button>
    </div>

    <template v-if="tab === 'usuarios'">
    <div class="flex flex-wrap gap-2">
      <span class="chip">Total: {{ usrs.length }}</span>
      <span class="chip">Activos: {{ usrs.filter(u => u.activo).length }}</span>
      <span class="badge border-amber-200 bg-amber-50 text-amber-800">Sin primer acceso: {{ usrs.filter(u => u.primer_acceso).length }}</span>
      <span class="badge border-line bg-white text-mut">Con acuse de instructivo: {{ usrs.filter(u => u.acuse_instructivo).length }}</span>
    </div>

    <div class="card p-3.5 grid grid-cols-2 sm:grid-cols-4 gap-2">
      <input v-model="uF.q" class="inp !py-2 text-[12.5px] col-span-2 sm:col-span-1" placeholder="Nombre o cédula…">
      <select v-model="uF.rol" class="inp !py-2 text-[12.5px]"><option value="">Rol: todos</option><option v-for="(l, k) in rolLbl" :key="k" :value="k">{{ l }}</option></select>
      <select v-model.number="uF.prov" class="inp !py-2 text-[12.5px]"><option value="">Provincia: todas</option><option v-for="p in provsOf('')" :key="p.id" :value="p.id">{{ p.nombre }}</option></select>
      <select v-model.number="uF.mun" class="inp !py-2 text-[12.5px]"><option value="">Municipio: todos</option><option v-for="m in munsFiltro" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}</option></select>
      <select v-model.number="uF.jce" class="inp !py-2 text-[12.5px]" :disabled="!distsFiltro.length"><option value="">Distrito: todos</option><option v-for="d in distsFiltro" :key="d.jce_id" :value="d.jce_id">{{ d.nombre }}{{ d.es_dm ? ' · DM' : '' }}</option></select>
      <select v-model="uF.ambito" class="inp !py-2 text-[12.5px]"><option value="">Ámbito: todos</option><option value="provincia">Provincial</option><option value="municipio">Municipal</option><option value="distrito">Distrital</option></select>
      <select v-model="uF.estado" class="inp !py-2 text-[12.5px]"><option value="">Estado: todos</option><option value="activos">Solo activos</option><option value="inactivos">Solo inactivos</option></select>
      <button class="btn-o btn-s" @click="uF = { q: '', rol: '', prov: '', mun: '', jce: '', ambito: '', estado: '' }">Limpiar</button>
    </div>




    <div class="card overflow-hidden">
      <div class="px-4 py-2.5 bg-fp-25 border-b border-fp-100 text-[11.5px] text-ink/80 leading-relaxed">
        <b>El PIN solo se ve una vez, al crearlo o al generarlo de nuevo.</b> Queda cifrado de forma irreversible: nadie —ni la Comisión— puede leerlo después.
        Usa <b class="text-fp-800">↺ PIN nuevo</b> cuando la persona no recuerde el suyo; <b>📱 Reenviar</b> manda solo el enlace, para quien ya lo tiene.
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[980px]">
          <thead class="bg-paper border-b border-line"><tr>
            <th v-for="col in [['nombre','Nombre'],['cedula','Cédula'],['rol','Rol'],['territorio','Territorio · Ámbito · Contacto'],['avance','Avance'],['acceso','Último acceso']]" :key="col[0]"
                class="th cursor-pointer select-none hover:text-ink" :class="uSort.c === col[0] ? 'text-fp-700' : ''" @click="ordenarPor(col[0])" title="Ordenar">{{ col[1] }}{{ flecha(col[0]) }}</th>
              <th class="th text-center cursor-pointer select-none hover:text-ink" :class="uSort.c === 'instructivo' ? 'text-fp-700' : ''" @click="ordenarPor('instructivo')">Instructivo{{ flecha('instructivo') }}</th>
              <th class="th cursor-pointer select-none hover:text-ink" :class="uSort.c === 'estado' ? 'text-fp-700' : ''" @click="ordenarPor('estado')">Estado{{ flecha('estado') }}</th>
              <th class="th text-right">Acciones</th>
          </tr></thead>
          <tbody>
            <tr v-for="u in usrsView" :key="u.id" class="border-b border-line/70">
              <td class="td font-semibold">{{ u.nombre }}<span class="block text-[10.5px] text-mut font-normal">{{ u.telefono || '' }}</span></td>
              <td class="td tabular-nums whitespace-nowrap">{{ fmtCed(u.cedula) }}</td>
              <td class="td whitespace-nowrap">
                <div>{{ rolLbl[u.rol] }}</div>
                <span class="inline-flex items-center gap-1 mt-1">
                  <span class="w-5 h-5 rounded-md grid place-items-center border"
                        :class="capacidad(u).digita ? 'bg-fp-600 text-white border-fp-600' : 'bg-paper text-line border-line'"
                        :title="capacidad(u).digita ? 'Puede registrar postulantes' : 'No puede registrar postulantes'">
                    <svg viewBox="0 0 24 24" class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
                  </span>
                  <span class="w-5 h-5 rounded-md grid place-items-center bg-fp-50 text-fp-700 border border-fp-200"
                        title="Puede consultar su territorio">
                    <svg viewBox="0 0 24 24" class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>
                  </span>
                  <span class="w-5 h-5 rounded-md grid place-items-center border"
                        :class="capacidad(u).imprime ? 'bg-ink/5 text-ink/70 border-line' : 'bg-paper text-line border-line'"
                        :title="capacidad(u).imprime ? 'Puede imprimir listados y reportes' : 'No puede imprimir'">
                    <svg viewBox="0 0 24 24" class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9V2h12v7"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 14h12v8H6z"/></svg>
                  </span>
                </span>
              </td>
                              <td class="td">
                  <div class="text-[13px]">{{ territorioDe(u) }}</div>
                  <div class="text-[11px] text-mut flex flex-wrap items-center gap-1.5 mt-0.5">
                    <span v-if="u.circ_codigo" class="badge border-fp-200 bg-fp-50 text-fp-800">Circ. {{ u.circ_codigo }}</span>
                    <span v-if="u.jce_id" class="badge border-line bg-paper text-mut">Distrito</span>
                    <span v-else-if="u.municipio_id" class="badge border-line bg-paper text-mut">Municipio</span>
                    <span v-else-if="u.provincia_id" class="badge border-line bg-paper text-mut">Provincial</span>
                    <span v-if="u.telefono">{{ fmtTel(u.telefono) }}</span>
                  </div>
                </td>
              <td class="td whitespace-nowrap">
                <template v-if="avance(u)">
                  <div class="text-[12px] tabular-nums"><b>{{ fmt(avance(u).total) }}</b> <span class="text-mut">de {{ fmt(avance(u).meta) }}</span> <span class="text-[10.5px] text-mut">· {{ avance(u).pct }}%</span></div>
                  <div class="h-1 w-24 rounded-full bg-line/70 overflow-hidden mt-1"><div class="h-full bg-fp-600" :style="{ width: avance(u).pct + '%' }"></div></div>
                  <div class="text-[10.5px] text-mut mt-0.5">{{ fmt(avance(u).colegios) }} colegios · meta ×3</div>
                </template>
                <span v-else class="text-[11px] text-mut">—</span>
              </td>
              <td class="td whitespace-nowrap"><span v-if="u.ultimo_acceso" class="text-[12px]">{{ fechaHora(u.ultimo_acceso) }}</span><span v-else class="badge border-amber-200 bg-amber-50 text-amber-800">Nunca</span></td>
              <td class="td text-center">
                <span v-if="u.acuse_instructivo" class="text-[11.5px] font-semibold text-fp-700 whitespace-nowrap">✓ {{ fecha(u.acuse_instructivo) }}</span>
                <span v-else class="badge border-amber-200 bg-amber-50 text-amber-800">Pendiente</span>
              </td>
              <td class="td"><button class="badge cursor-pointer" :class="u.activo ? 'border-fp-200 bg-fp-50 text-fp-800' : 'border-red-200 bg-red-50 text-red-700'" @click="toggleActivo(u)">{{ u.activo ? 'Activo' : 'Inactivo' }}</button></td>
              <td class="td text-right whitespace-nowrap">
                <button class="btn-o btn-s mr-1" title="Editar usuario" @click="abrirEdicion(u)">✎ Editar</button>
                <button v-if="u.rol !== 'admin_sne'" class="btn-p btn-s mr-1 !bg-[#25D366] hover:!bg-[#1ebe5b]" title="Genera un PIN nuevo, lo muestra y lo envía por WhatsApp" @click="resetPin(u)">↺ PIN nuevo</button>
                <button class="btn-o btn-s mr-1" title="Reenvía solo el enlace, sin PIN" @click="waAcceso(u)">📱 Reenviar</button>
                <button class="btn-o btn-s" @click="copiarAcceso(u)">Copiar</button>
              </td>
            </tr>
            <tr v-if="!usrsView.length && !uBusy"><td colspan="8" class="td text-center text-mut py-10">Sin usuarios. Crea el primero con <b>Nuevo usuario</b>.</td></tr>
            <tr v-if="uBusy"><td colspan="8" class="td text-center text-mut py-10">Cargando…</td></tr>
          </tbody>
        </table>
      </div>
    </div>
    </template>

    <!-- ═ Modal: crear usuario ═ -->
    <div v-if="ed" class="modal fixed inset-0 z-50 bg-ink/40 p-3 sm:p-6 flex items-start sm:items-center justify-center overflow-y-auto" @click.self="ed = null">
      <div class="card w-full max-w-lg p-5 my-auto">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="font-serif font-bold text-[17px]">Editar usuario</h3>
            <p class="text-[12px] text-mut">{{ fmtCed(ed.cedula) }} · la cédula no se modifica</p>
          </div>
          <button class="w-8 h-8 rounded-lg border border-line grid place-items-center text-mut hover:text-ink" @click="ed = null">✕</button>
        </div>

        <div class="space-y-3">
          <div><label class="lbl">Nombre completo</label><input v-model="ed.nombre" class="inp"></div>
          <div><label class="lbl">Teléfono / WhatsApp</label><input :value="ed.telefono" @input="ed.telefono = fmtTel($event.target.value)" class="inp" inputmode="tel" placeholder="809-000-0000" maxlength="12"></div>
          <div>
            <label class="lbl">Rol</label>
            <select v-model="ed.rol" class="inp">
              <option v-for="(l, k) in rolLbl" :key="k" :value="k" :disabled="k === 'admin_sne'">{{ l }}</option>
            </select>
          </div>

          <div v-if="['presidente','secretario_general','enc_electoral'].includes(ed.rol)">
            <label class="lbl">Ámbito de su cargo</label>
            <select v-model="ed.ambito" class="inp" @change="ed.mun = 0; ed.jce = 0; ed.prov = 0; edDists = []">
              <option value="municipio">Municipio o distrito</option>
              <option value="provincia">Provincia completa</option>
            </select>
          </div>

          <div v-if="['presidente','secretario_general','enc_electoral'].includes(ed.rol) && ed.ambito === 'provincia'">
            <label class="lbl">Provincia</label>
            <select v-model.number="ed.prov" class="inp">
              <option :value="0">Seleccionar…</option>
              <option v-for="p in provsOf('')" :key="p.id" :value="p.id">{{ p.nombre }}</option>
            </select>
          </div>

          <div v-if="['presidente','secretario_general','enc_electoral'].includes(ed.rol) && ed.ambito !== 'provincia'">
            <label class="lbl">Municipio</label>
            <select v-model.number="ed.mun" class="inp" @change="edCargarDists(ed.mun)">
              <option :value="0">Seleccionar…</option>
              <optgroup v-for="g in catGrupos" :key="g.prov" :label="g.prov">
                <option v-for="m in g.items" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}{{ m.tipo === 'OCLEE' ? ' · OCLEE' : '' }}</option>
              </optgroup>
            </select>
          </div>

          <div v-if="edCircs.length > 1 && ed.ambito !== 'provincia'">
            <label class="lbl">Circunscripción</label>
            <select v-model="ed.circ" class="inp">
              <option value="">Todo el municipio</option>
              <option v-for="c in edCircs" :key="c.circ_codigo" :value="c.circ_codigo">{{ c.circ_nombre || ('Circunscripción ' + c.circ_codigo) }}</option>
            </select>
          </div>

          <div v-if="['presidente','secretario_general','enc_electoral'].includes(ed.rol) && ed.ambito !== 'provincia' && edDists.length > 1">
            <label class="lbl">Distrito (si se elige, la persona solo verá ese distrito)</label>
            <select v-model.number="ed.jce" class="inp">
              <option :value="0">Todo el municipio</option>
              <option v-for="d in edDists" :key="d.jce_id" :value="d.jce_id">{{ d.nombre }}{{ d.es_dm ? ' · DM' : '' }} — {{ d.colegios }} colegios</option>
            </select>
          </div>

          <div v-if="ed.rol === 'supervisor_provincial'">
            <label class="lbl">Provincia</label>
            <select v-model.number="ed.prov" class="inp">
              <option :value="0">Seleccionar…</option>
              <option v-for="p in provsOf('')" :key="p.id" :value="p.id">{{ p.nombre }}</option>
            </select>
          </div>

          <div v-if="ed.rol === 'coordinador_regional'">
            <label class="lbl">Región</label>
            <select v-model="ed.region" class="inp">
              <option value="">Seleccionar…</option>
              <option v-for="r in regiones" :key="r" :value="r">{{ r }}</option>
            </select>
          </div>

          <div class="rounded-xl border border-line bg-paper p-3 space-y-2">
            <div class="text-[11px] font-bold uppercase tracking-wider text-mut">Configuración</div>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="ed.verD" class="accent-fp-600 w-4 h-4">
              <span class="text-[12.5px] leading-snug">Ver el desglose por <b>distrito</b> de su municipio<span class="block text-[11px] text-mut">Activado: ve la tabla de sus distritos y puede filtrar por cada uno. Desactivado: ve el municipio como un solo bloque.</span></span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" :checked="ed.puedeImp !== false" @change="ed.puedeImp = $event.target.checked ? null : false" class="accent-fp-600 w-4 h-4">
              <span class="text-[12.5px]">Autorizar a <b>imprimir</b> listados y reportes</span>
            </label>
            <label class="flex items-start gap-2 cursor-pointer rounded-lg border p-2.5 transition-colors"
                   :class="regEfectivo(ed) ? 'border-fp-300 bg-fp-25' : 'border-line bg-white'">
              <input type="checkbox" :checked="regEfectivo(ed)"
                     @change="ed.puedeReg = $event.target.checked ? true : false"
                     class="accent-fp-600 mt-0.5 w-4 h-4">
              <span class="text-[12.5px] leading-snug">
                Puede <b>registrar</b> postulantes
                <span class="block text-[11px] text-mut mt-0.5">
                  Por norma registra el Encargado(a) Electoral de un municipio o distrito.
                  La dirigencia provincial, los presidentes y los secretarios consultan e imprimen.
                </span>
              </span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="ed.activo" class="accent-fp-600 w-4 h-4">
              <span class="text-[12.5px]">Acceso <b>activo</b></span>
            </label>
          </div>

          <div v-if="edErr" class="errbx">{{ edErr }}</div>

          <div class="flex gap-2 pt-1">
            <button class="btn-p flex-1" :disabled="edBusy" @click="guardarEdicion">{{ edBusy ? 'Guardando…' : 'Guardar cambios' }}</button>
            <button class="btn-o" @click="ed = null">Cancelar</button>
          </div>
          <div class="rounded-xl border border-line bg-paper p-3 space-y-2">
            <div class="text-[11px] font-bold uppercase tracking-wider text-mut">PIN de acceso</div>
            <label class="flex items-start gap-2 cursor-pointer">
              <input type="checkbox" v-model="ed.forzar" class="accent-fp-600 mt-0.5 w-4 h-4">
              <span class="text-[12.5px] leading-snug">Obligar a crear un <b>PIN nuevo</b> en el próximo ingreso<span class="block text-[11px] text-mut">Mantiene su PIN actual, pero el sistema no lo dejará avanzar hasta que lo cambie.</span></span>
            </label>
            <button v-if="ed.rol !== 'admin_sne'" class="btn-o btn-s w-full" @click="resetDesdeEdicion">↺ Generar un PIN nuevo y enviarlo por WhatsApp</button>
            <p class="text-[11px] text-mut leading-relaxed">Nadie puede ver el PIN actual — está cifrado de forma irreversible. Solo se puede reemplazar.</p>
          </div>
        </div>
      </div>
    </div>

    <div v-if="showCrear" class="modal fixed inset-0 z-50 bg-ink/40 p-3 sm:p-6 flex items-start sm:items-center justify-center overflow-y-auto" @click.self="showCrear = false">
      <div class="card w-full max-w-lg max-h-[92vh] overflow-y-auto">
        <div class="p-4 border-b border-line flex items-center justify-between sticky top-0 bg-white rounded-t-2xl">
          <div class="font-serif font-bold text-[16px]">Nuevo usuario territorial</div>
          <button class="w-8 h-8 rounded-lg border border-line grid place-items-center text-mut hover:text-ink" @click="showCrear = false">✕</button>
        </div>

        <div v-if="!cuOk" class="p-4 space-y-3.5">
          <div>
            <label class="lbl">Cédula</label>
            <div class="flex gap-2">
              <input v-model="cu.ced" class="inp" inputmode="numeric" placeholder="000-0000000-0" @keyup.enter="buscarCedU">
              <button class="btn-o shrink-0" @click="buscarCedU" :disabled="cuBusy">Verificar</button>
            </div>
            <div v-if="cu.lkpU && cu.lkpU.encontrado" class="okbx mt-2 !py-2 text-[12.5px]">✓ {{ cu.lkpU.nombres }} {{ cu.lkpU.apellido1 }} · vota en {{ cu.lkpU.municipio_app || cu.lkpU.jce_municipio }}</div>
            <div v-if="cu.lkpU && !cu.lkpU.encontrado" class="errbx mt-2 !py-2 text-[12.5px]">Cédula no encontrada en el padrón. Verifícala antes de continuar.</div>
          </div>
          <div><label class="lbl">Nombre completo</label><input v-model="cu.nombre" class="inp" placeholder="Se completa desde el padrón"></div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="lbl">Teléfono</label><input :value="cu.telefono" @input="cu.telefono = fmtTel($event.target.value)" class="inp" inputmode="tel" placeholder="809-000-0000" maxlength="12"></div>
            <div><label class="lbl">Rol</label><select v-model="cu.rol" class="inp"><option v-for="(l, k) in rolLbl" :key="k" :value="k">{{ l }}</option></select></div>
          </div>
          <div v-if="['presidente','secretario_general','enc_electoral'].includes(cu.rol)">
            <label class="lbl">Municipio / DM / OCLEE</label>
            <select v-model.number="cu.mun" class="inp" @change="cargarDistsU(cu.mun)">
              <option :value="0" disabled>Seleccionar…</option>
              <optgroup v-for="g in catGrupos" :key="g.prov" :label="g.prov"><option v-for="m in g.items" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}{{ m.tipo === 'OCLEE' ? ' · OCLEE' : '' }}</option></optgroup>
            </select>
            <div v-if="distsU.length > 1" class="mt-2">
              <label class="lbl">Distrito (opcional · si se elige, la persona solo verá ese distrito)</label>
              <select v-model.number="cu.jce" class="inp">
                <option :value="0">Todo el municipio</option>
                <option v-for="d in distsU" :key="d.jce_id" :value="d.jce_id">{{ d.nombre }}{{ d.es_dm ? ' · DM' : '' }} — {{ d.colegios }} colegios</option>
              </select>
            </div>
            <div class="mt-3 rounded-xl border border-line bg-paper p-3 space-y-2">
              <div class="text-[11px] font-bold uppercase tracking-wider text-mut">Configuración de alcance</div>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" v-model="cu.verD" class="accent-fp-600 w-4 h-4">
                <span class="text-[12.5px] leading-snug">Ver el desglose por <b>distrito</b> de su municipio<span class="block text-[11px] text-mut">Activado: ve la tabla de sus distritos y puede filtrar por cada uno. Desactivado: ve el municipio como un solo bloque.</span></span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" :checked="cu.puedeImp !== false" @change="cu.puedeImp = $event.target.checked ? null : false" class="accent-fp-600 w-4 h-4">
                <span class="text-[12.5px]">Autorizar a <b>imprimir</b> listados y reportes</span>
              </label>
              <label v-if="!['enc_electoral','admin_sne'].includes(cu.rol)"
                     class="flex items-start gap-2 cursor-pointer rounded-lg border p-2.5 transition-colors"
                     :class="cu.puedeReg === true ? 'border-amber-300 bg-amber-50' : 'border-line bg-white'">
                <input type="checkbox" :checked="cu.puedeReg === true" @change="cu.puedeReg = $event.target.checked ? true : null" class="accent-amber-600 mt-0.5 w-4 h-4">
                <span class="text-[12.5px] leading-snug">
                  <b>Excepción:</b> autorizar además a <b>registrar</b> postulantes
                  <span class="block text-[11px] text-mut mt-0.5">Por norma solo registra el Encargado(a) Electoral. Deja esta casilla <b>sin marcar</b> salvo instrucción expresa de la Comisión.</span>
                </span>
              </label>
            </div>
            <div v-if="cu.lkpU?.encontrado && cu.mun && cu.lkpU.municipio_app_id && cu.lkpU.municipio_app_id !== cu.mun" class="warn mt-2 !py-2 text-[12px]">Ojo: según el padrón vota en <b>{{ cu.lkpU.municipio_app }}</b>, distinto al territorio asignado.</div>
          </div>
          <div v-if="cu.rol === 'supervisor_provincial'"><label class="lbl">Provincia</label><select v-model.number="cu.prov" class="inp"><option :value="0" disabled>Seleccionar…</option><option v-for="p in provsOf('')" :key="p.id" :value="p.id">{{ p.nombre }}</option></select></div>
          <div v-if="cu.rol === 'coordinador_regional'"><label class="lbl">Región</label><select v-model="cu.region" class="inp"><option value="" disabled>Seleccionar…</option><option v-for="r in regiones" :key="r" :value="r">{{ r }}</option></select></div>
          <div>
            <label class="lbl">PIN inicial · se muestra una sola vez al crear</label>
            <div class="flex gap-2"><input v-model="cu.pin" class="inp font-mono tracking-widest"><button class="btn-o shrink-0" @click="cu.pin = genPin()">↻</button></div>
            <div class="text-[11px] text-mut mt-1">El sistema le exigirá cambiarlo en su primer ingreso.</div>
          </div>
          <div v-if="cuErr" class="errbx text-[12.5px]">{{ cuErr }}</div>
          <div v-if="cuPend" class="warn text-[12px]">La cuenta de acceso se creó pero el perfil no se guardó. <button class="underline font-bold" @click="reintentarPerfil">Reintentar guardar perfil</button></div>
          <button class="btn-p w-full" :disabled="cuBusy || !cu.ced || !cu.nombre || !cu.pin" @click="crearUsuario">{{ cuBusy ? 'Creando…' : 'Crear acceso' }}</button>
        </div>

        <div v-else class="p-4 space-y-3">
          <div class="okbx"><b>{{ cuOk.reset ? 'PIN restablecido.' : 'Acceso creado.' }}</b> Comparte este mensaje por WhatsApp con {{ cuOk.nombre }}:</div>

          <div class="rounded-xl border-2 border-fp-600 bg-fp-25 p-4 my-3 text-center">
            <div class="text-[10.5px] font-bold uppercase tracking-[0.18em] text-fp-700 mb-1">PIN inicial · anótalo ahora</div>
            <div class="font-mono text-[30px] font-bold tracking-[0.3em] text-ink select-all">{{ cuOk.pin }}</div>
            <button class="btn-o btn-s mt-2" @click="copiar(cuOk.pin)">Copiar solo el PIN</button>
            <p class="text-[11px] text-mut mt-2 leading-relaxed">Este PIN <b>no se puede volver a ver</b>: queda cifrado de forma irreversible. Si se pierde, se restablece con el botón <b>↺ PIN</b> de la fila.</p>
          </div>
          <textarea class="inp min-h-[190px] text-[12.5px] font-mono" readonly :value="cuOk.msg"></textarea>
          <div class="flex gap-2">
            <a class="btn-p flex-1 text-center !bg-[#25D366] hover:!bg-[#1ebe5b]" :href="waLink(cuOk.tel, cuOk.msg)" target="_blank" rel="noopener">📱 Enviar por WhatsApp</a>
            <button class="btn-p flex-1" @click="copiar(cuOk.msg)">Copiar mensaje</button>
            <button class="btn-o" @click="cuOk = null; showCrear = false">Cerrar</button>
          </div>
        </div>
      </div>
    </div>
    <template v-if="tab === 'accesos'">
    <p class="text-[12px] text-mut">Cuatro bandejas independientes. Cada una se pliega con su título; los números del menú te dicen dónde hay trabajo.</p>
    <div class="card overflow-hidden border-amber-200">
      <div class="p-4 border-b border-line bg-amber-50/60 flex items-center gap-2 cursor-pointer select-none" @click="abre.solis = !abre.solis">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Solicitudes de PIN pendientes</h3>
        <span class="badge border-amber-300 bg-amber-100 text-amber-900">{{ solis.length }}</span>
        <button class="btn-o btn-s" @click.stop="cargarSolis">Actualizar</button>
        <span class="text-mut text-[13px]">{{ abre.solis ? '▴' : '▾' }}</span>
      </div>
<div v-show="abre.solis">      <table class="w-full">
        <tbody>
          <tr v-if="!solis.length"><td class="td text-center text-mut py-6" colspan="4">Sin solicitudes pendientes.</td></tr>
          <tr v-for="sx in solis" :key="sx.id" class="border-b border-line/60">
            <td class="td font-semibold">{{ sx.nombre }}<span class="block text-[10.5px] text-mut font-normal">{{ fmtCed(sx.cedula) }}</span></td>
            <td class="td text-mut text-[12px] whitespace-nowrap">{{ rolLbl[sx.rol] || '' }}</td>
            <td class="td text-mut text-[12px] whitespace-nowrap">{{ fechaHora(sx.created_at) }}</td>
            <td class="td text-right whitespace-nowrap">
              <button v-if="sx.rol && sx.rol !== 'admin_sne'" class="btn-p btn-s" @click="resetPin({ cedula: sx.cedula, nombre: sx.nombre, rol: sx.rol, telefono: sx.telefono, municipio_id: null })">↺ Restablecer y enviar</button>
              <span v-else class="text-[11.5px] text-mut">Sin acceso registrado</span>
            </td>
          </tr>
        </tbody>
      </table>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">Solicitadas desde la pantalla de acceso. Al restablecer, la solicitud se cierra sola.</div></div>
    </div>

    <!-- ══ Usuarios bloqueados (fase 74) ══ -->
    <div class="card overflow-hidden border-red-200">
      <div class="p-4 border-b border-line bg-red-50/60 flex items-center gap-2 cursor-pointer select-none" @click="abre.bloqueados = !abre.bloqueados">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Usuarios bloqueados</h3>
        <span class="badge border-red-300 bg-red-100 text-red-900">{{ bloqueados.length }}</span>
        <button class="btn-o btn-s" @click.stop="cargarBandejas">Actualizar</button>
        <span class="text-mut text-[13px]">{{ abre.bloqueados ? '▴' : '▾' }}</span>
      </div>
<div v-show="abre.bloqueados">      <table class="w-full"><tbody>
        <tr v-if="!bloqueados.length"><td class="td text-center text-mut py-6" colspan="3">Nadie está bloqueado.</td></tr>
        <tr v-for="b in bloqueados" :key="b.id" class="border-b border-line/60">
          <td class="td font-semibold">{{ b.nombre }}<span class="block text-[10.5px] text-mut font-normal">{{ fmtCed(b.cedula) }} · {{ rolLbl[b.rol] || b.rol }}</span></td>
          <td class="td text-[12px]">
            <span class="badge" :class="b.tipo === 'definitivo' ? 'border-red-300 bg-red-50 text-red-800' : 'border-amber-300 bg-amber-50 text-amber-800'">{{ b.tipo === 'definitivo' ? 'Bloqueo definitivo' : 'Temporal hasta ' + fechaHora(b.hasta) }}</span>
            <span v-if="b.motivo" class="block text-[11px] text-mut mt-0.5">{{ b.motivo }}</span>
          </td>
          <td class="td text-right whitespace-nowrap"><button class="btn-p btn-s" :disabled="segAccion === b.id" @click="desbloquear(b)">Habilitar</button></td>
        </tr>
      </tbody></table>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">Habilitar pone los intentos en cero y levanta el bloqueo. Queda en la bitácora.</div></div>
    </div>

    <!-- ══ Accesos por confirmar (fase 74) ══ -->
    <div class="card overflow-hidden border-sky-200">
      <div class="p-4 border-b border-line bg-sky-50/60 flex items-center gap-2 cursor-pointer select-none" @click="abre.confirmar = !abre.confirmar">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Primeros ingresos por confirmar</h3>
        <span class="badge border-sky-300 bg-sky-100 text-sky-900">{{ porConfirmar.length }}</span>
        <button class="btn-o btn-s" @click.stop="cargarBandejas">Actualizar</button>
        <span class="text-mut text-[13px]">{{ abre.confirmar ? '▴' : '▾' }}</span>
      </div>
<div v-show="abre.confirmar">      <table class="w-full"><tbody>
        <tr v-if="!porConfirmar.length"><td class="td text-center text-mut py-6" colspan="3">No hay primeros ingresos por confirmar.</td></tr>
        <tr v-for="c in porConfirmar" :key="c.id" class="border-b border-line/60">
          <td class="td font-semibold">{{ c.nombre }}<span class="block text-[10.5px] text-mut font-normal">{{ fmtCed(c.cedula) }} · {{ rolLbl[c.rol] || c.rol }} · {{ c.territorio }}</span></td>
          <td class="td text-[12px] text-mut">Entró {{ fechaHora(c.primer_ingreso_en) }}<span v-if="c.telefono"> · {{ fmtTel(c.telefono) }}</span>
            <span class="block text-[11px]" :class="c.verificado ? 'text-fp-700' : 'text-amber-700'">{{ c.verificado ? '✓ Verificó su identidad con el padrón' : 'Aún no verifica identidad con el padrón' }}</span></td>
          <td class="td text-right whitespace-nowrap">
            <button class="btn-p btn-s" :disabled="segAccion === c.id" @click="confirmarAcceso(c, true)">Confirmar identidad</button>
            <button class="btn-o btn-s ml-1" :disabled="segAccion === c.id" @click="confirmarAcceso(c, false)">Desactivar</button>
          </td>
        </tr>
      </tbody></table>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">Llama a la persona y confirma que es quien debe ser. Hasta que confirmes, puede consultar pero no registrar.</div></div>
    </div>

    <!-- ══ Accesos por enviar (fase 74) ══ -->
    <div class="card overflow-hidden border-fp-200">
      <div class="p-4 border-b border-line bg-fp-25 flex flex-wrap items-center gap-2 cursor-pointer select-none" @click="abre.enviar = !abre.enviar">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Accesos por enviar</h3>
        <span class="chip">{{ pinesEnviar.length }} pendientes · {{ pinesEnviar.filter(x => x.vencido).length }} vencidos</span>
        <button class="btn-p btn-s" @click.stop="enviarSiguiente">📱 Enviar siguiente por WhatsApp</button>
        <span class="text-mut text-[13px]">{{ abre.enviar ? '▴' : '▾' }}</span>
      </div>
<div v-show="abre.enviar">      <table class="w-full"><tbody>
        <tr v-if="!pinesEnviar.length"><td class="td text-center text-mut py-6" colspan="3">Todos los accesos fueron enviados.</td></tr>
        <tr v-for="r in pinesEnviar.slice(0, 50)" :key="r.cedula" class="border-b border-line/60">
          <td class="td font-semibold">{{ r.nombre }}<span class="block text-[10.5px] text-mut font-normal">{{ fmtCed(r.cedula) }} · {{ rolLbl[r.rol] || r.rol }} · {{ r.territorio }}</span></td>
          <td class="td text-[12px] text-mut whitespace-nowrap">{{ r.telefono ? fmtTel(r.telefono) : 'sin teléfono' }}<span v-if="r.vencido" class="badge border-red-200 bg-red-50 text-red-700 ml-1">PIN vencido</span><span v-else class="block text-[10.5px]">vence {{ fechaHora(r.caduca_en) }}</span></td>
          <td class="td text-right whitespace-nowrap"><button class="btn-o btn-s" :disabled="r.vencido || !r.telefono" @click="enviarPin(r)">Enviar</button></td>
        </tr>
      </tbody></table>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">Cada envío abre WhatsApp con el mensaje y el PIN, y al volver queda marcado como entregado con tu nombre y la hora.<span v-if="pinesEnviar.length > 50"> Se muestran 50 de {{ pinesEnviar.length }}.</span></div></div>
    </div>
    </template>

    <template v-if="tab === 'asistente'">
    <!-- Consultas por WhatsApp y Telegram -->
    <div class="card overflow-hidden">
      <div class="p-4 border-b border-line flex flex-wrap items-center gap-2 cursor-pointer" @click="waOpen = !waOpen">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Asistente de consulta</h3>
        <span class="chip">{{ wa.filter(w => w.activo).length + tg.filter(w => w.activo).length }} autorizados</span>
        <span class="text-mut text-[13px]">{{ waOpen ? '▴' : '▾' }}</span>
      </div>

      <div v-if="waOpen">
        <div class="px-4 py-3 bg-fp-25 border-b border-fp-100 text-[11.5px] text-ink/80 leading-relaxed">
          Quien esté autorizado puede consultar el avance de su territorio desde el celular, escribiéndole al asistente
          la palabra <b>avance</b> para el resumen nacional, o el nivel seguido del nombre —<b>región</b>, <b>provincia</b>
          o <b>municipio</b>— para ver esa demarcación con su cobertura de colegios.
          <span class="block mt-1">Las respuestas contienen <b>solo cifras de avance</b>: nunca nombres, cédulas ni datos de contacto.
          Quien tenga alcance de <b>Administración</b> puede además restablecer el PIN de un usuario. Cada consulta queda registrada en Actividad.</span>
        </div>

        <div class="px-4 pt-3 flex gap-2">
          <button class="btn-s" :class="canal === 'whatsapp' ? 'btn-p' : 'btn-o'" @click="canal = 'whatsapp'">WhatsApp</button>
          <button class="btn-s" :class="canal === 'telegram' ? 'btn-p' : 'btn-o'" @click="canal = 'telegram'">Telegram</button>
        </div>

        <div v-if="canal === 'whatsapp'" class="p-4 border-b border-line grid sm:grid-cols-2 lg:grid-cols-4 gap-2 items-end">
          <div>
            <label class="lbl">Teléfono</label>
            <input v-model="waF.tel" class="inp !py-2 text-[13px]" placeholder="809 555 1234" inputmode="numeric">
          </div>
          <div>
            <label class="lbl">Usuario del portal</label>
            <select v-model="waF.ced" class="inp !py-2 text-[13px]" @change="alElegirUsrWa">
              <option value="">Sin enlazar (externo)</option>
              <option v-for="u in usrsEnlazables" :key="u.id" :value="u.cedula">{{ u.nombre }} — {{ rolLbl[u.rol] || u.rol }}</option>
            </select>
          </div>
          <div>
            <label class="lbl">Descripción</label>
            <input v-model="waF.desc" class="inp !py-2 text-[13px]" placeholder="Ej. Coordinador Región Sur">
          </div>
          <div>
            <label class="lbl">Alcance</label>
            <select v-model="waF.rol" class="inp !py-2 text-[13px]">
              <option value="consulta">Consulta de avance</option>
              <option value="admin">Administración (además restablece PIN)</option>
            </select>
          </div>
          <button class="btn-p !py-2" :disabled="waBusy" @click="guardarWa">{{ waBusy ? 'Autorizando…' : '+ Autorizar número' }}</button>
          <div v-if="waErr" class="errbx sm:col-span-2 lg:col-span-5">{{ waErr }}</div>
        </div>

        <div v-if="canal === 'whatsapp'" class="overflow-x-auto">
          <table class="w-full min-w-[620px]">
            <thead class="bg-paper border-b border-line"><tr>
              <th class="th">Número</th><th class="th">¿De quién es? · Usuario enlazado</th><th class="th">Alcance</th>
              <th class="th">Última consulta</th><th class="th text-right">Acciones</th>
            </tr></thead>
            <tbody>
              <tr v-for="w in wa" :key="w.telefono" class="border-b border-line/60" :class="w.activo ? '' : 'opacity-55'">
                <td class="td font-mono text-[12.5px] whitespace-nowrap">{{ waPretty(w.telefono) }}</td>
                <td class="td">
                  <div class="font-semibold">{{ w.descripcion }}</div>
                  <div v-if="w.cedula" class="text-[11px] text-fp-700">↳ {{ nombreDeCedula(w.cedula) || fmtCed(w.cedula) }}</div>
                  <div v-else class="text-[11px] text-mut">Sin enlazar a un usuario</div>
                </td>
                <td class="td">
                  <span class="badge" :class="w.rol === 'admin' ? 'border-amber-300 bg-amber-50 text-amber-800' : 'border-line bg-paper text-mut'">
                    {{ w.rol === 'admin' ? 'Administración' : 'Consulta' }}
                  </span>
                </td>
                <td class="td text-[12px] text-mut whitespace-nowrap">{{ w.ultimo_uso ? fechaHora(w.ultimo_uso) : 'Sin consultas aún' }}</td>
                <td class="td text-right whitespace-nowrap">
                  <button class="btn-o btn-s mr-1" @click="waEstado(w)">{{ w.activo ? 'Revocar' : 'Reactivar' }}</button>
                  <button class="btn-o btn-s" @click="waBaja(w)">Eliminar</button>
                </td>
              </tr>
              <tr v-if="!wa.length"><td colspan="5" class="td text-center text-mut py-8">Ningún número autorizado todavía.</td></tr>
            </tbody>
          </table>
        </div>
        <div v-if="canal === 'whatsapp'" class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
          Mientras se use la línea de prueba de Meta, el número debe estar registrado también del lado de Meta.
        </div>

        <!-- Telegram -->
        <div v-if="canal === 'telegram'" class="p-4 border-b border-line grid sm:grid-cols-2 lg:grid-cols-5 gap-2 items-end">
          <div>
            <label class="lbl">Identificador de chat</label>
            <input v-model="tgF.chat" class="inp !py-2 text-[13px]" placeholder="Ej. 1234567890" inputmode="numeric">
          </div>
          <div>
            <label class="lbl">Usuario del portal</label>
            <select v-model="tgF.ced" class="inp !py-2 text-[13px]" @change="alElegirUsrTg">
              <option value="">Sin enlazar (externo)</option>
              <option v-for="u in usrsEnlazables" :key="u.id" :value="u.cedula">{{ u.nombre }} — {{ rolLbl[u.rol] || u.rol }}</option>
            </select>
          </div>
          <div>
            <label class="lbl">Descripción</label>
            <input v-model="tgF.desc" class="inp !py-2 text-[13px]" placeholder="Ej. Coordinador Región Sur">
          </div>
          <div>
            <label class="lbl">Alcance</label>
            <select v-model="tgF.rol" class="inp !py-2 text-[13px]">
              <option value="consulta">Consulta de avance</option>
              <option value="admin">Administración (además restablece PIN)</option>
            </select>
          </div>
          <button class="btn-p !py-2" :disabled="tgBusy" @click="guardarTg">{{ tgBusy ? 'Autorizando…' : '+ Autorizar acceso' }}</button>
          <div v-if="tgErr" class="errbx sm:col-span-2 lg:col-span-5">{{ tgErr }}</div>
          <div class="sm:col-span-2 lg:col-span-5 text-[11px] text-mut">
            La persona obtiene su identificador escribiéndole <b>/id</b> al asistente; te lo comparte y lo registras aquí.
          </div>
        </div>

        <div v-if="canal === 'telegram'" class="overflow-x-auto">
          <table class="w-full min-w-[620px]">
            <thead class="bg-paper border-b border-line"><tr>
              <th class="th">Identificador</th><th class="th">¿De quién es? · Usuario enlazado</th><th class="th">Alcance</th>
              <th class="th">Última consulta</th><th class="th text-right">Acciones</th>
            </tr></thead>
            <tbody>
              <tr v-for="w in tg" :key="w.chat_id" class="border-b border-line/60" :class="w.activo ? '' : 'opacity-55'">
                <td class="td font-mono text-[12.5px] whitespace-nowrap">{{ w.chat_id }}</td>
                <td class="td">
                  <div class="font-semibold">{{ w.descripcion }}</div>
                  <div v-if="w.cedula" class="text-[11px] text-fp-700">↳ {{ nombreDeCedula(w.cedula) || fmtCed(w.cedula) }}</div>
                  <div v-else class="text-[11px] text-mut">Sin enlazar a un usuario</div>
                </td>
                <td class="td">
                  <span class="badge" :class="w.rol === 'admin' ? 'border-amber-300 bg-amber-50 text-amber-800' : 'border-line bg-paper text-mut'">
                    {{ w.rol === 'admin' ? 'Administración' : 'Consulta' }}
                  </span>
                </td>
                <td class="td text-[12px] text-mut whitespace-nowrap">{{ w.ultimo_uso ? fechaHora(w.ultimo_uso) : 'Sin consultas aún' }}</td>
                <td class="td text-right whitespace-nowrap">
                  <button class="btn-o btn-s mr-1" @click="tgEstado(w)">{{ w.activo ? 'Revocar' : 'Reactivar' }}</button>
                  <button class="btn-o btn-s" @click="tgBaja(w)">Eliminar</button>
                </td>
              </tr>
              <tr v-if="!tg.length"><td colspan="5" class="td text-center text-mut py-8">Ningún acceso autorizado todavía.</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    </template>

    <template v-if="tab === 'config'">
    <!-- Índice de la configuración -->
    <div class="flex flex-wrap gap-2">
      <a class="btn-o btn-s" @click.prevent="irA('config-traslados')">⇄ Traslados y asignación</a>
      <a class="btn-o btn-s" @click.prevent="irA('config-seguridad')">⛨ Seguridad del acceso</a>
      <a class="btn-o btn-s" @click.prevent="irA('config-sello')">⎙ Marca de agua</a>
      <a class="btn-o btn-s" @click.prevent="irA('config-formularios')">▤ Formularios habilitados</a>
      <a class="btn-o btn-s" @click.prevent="irA('permisos-rol')">⚿ Permisos por rol</a>
    </div>

    <!-- ══ Seguridad del acceso: captcha ══ -->
    <section id="config-seguridad" class="card p-4 scroll-mt-20">
      <h3 class="font-serif text-[15px] font-bold mb-1">Seguridad del acceso</h3>
      <p class="text-[12px] text-mut mb-4 max-w-[76ch]">
        El captcha de Cloudflare (Turnstile) frena los intentos automáticos de adivinar PIN. Se muestra en la
        pantalla de acceso y no requiere que el usuario escriba nada: en la mayoría de los casos pasa solo.
      </p>
      <label class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer transition-colors"
             :class="cfgSeg.captcha_activo ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
        <input type="checkbox" v-model="cfgSeg.captcha_activo" class="accent-fp-600 w-4 h-4 mt-0.5">
        <span>
          <b class="text-[13.5px]">Exigir verificación de seguridad al entrar</b>
          <span class="block text-[11.5px] text-mut leading-snug mt-0.5">Necesita la Site Key del widget creado en Cloudflare → Turnstile.</span>
        </span>
      </label>
      <div class="mt-3 max-w-[520px]">
        <label class="lbl">Site Key de Turnstile</label>
        <input v-model.trim="cfgSeg.captcha_site_key" class="inp font-mono text-[12.5px]" placeholder="0x4AAAAAAA…" autocomplete="off" spellcheck="false">
      </div>
      <p class="text-[11.5px] text-mut mt-3 leading-snug max-w-[76ch]">
        La verificación la hace la función de acceso del servidor con la clave secreta de Turnstile
        (secreto TURNSTILE_SECRET). Si no hay clave secreta configurada, el reto se muestra pero no se exige.
        En el panel de la base de datos el captcha debe quedar apagado.
      </p>
      <div class="mt-5 pt-4 border-t border-line space-y-3">
        <p class="text-[13.5px] font-semibold">Capas de protección del acceso</p>

        <label class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer" :class="cfgSeg.bloqueo_activo ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
          <input type="checkbox" v-model="cfgSeg.bloqueo_activo" class="accent-fp-600 w-4 h-4 mt-0.5">
          <span class="min-w-0">
            <b class="text-[13.5px]">Bloqueo por intentos fallidos</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">A partir de <input type="number" min="1" max="20" v-model.number="cfgSeg.intentos_aviso" class="inp !inline-block !w-14 !py-0.5 !px-1.5 text-center mx-1" @click.stop> fallos avisa cuántos quedan; al llegar a <input type="number" min="2" max="30" v-model.number="cfgSeg.intentos_bloqueo" class="inp !inline-block !w-14 !py-0.5 !px-1.5 text-center mx-1" @click.stop> bloquea <input type="number" min="1" max="1440" v-model.number="cfgSeg.bloqueo_minutos" class="inp !inline-block !w-16 !py-0.5 !px-1.5 text-center mx-1" @click.stop> minutos. Si vuelve a agotarlos, bloqueo definitivo: solo se habilita desde «Usuarios bloqueados».</span>
          </span>
        </label>

        <label class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer" :class="cfgSeg.verificar_padron ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
          <input type="checkbox" v-model="cfgSeg.verificar_padron" class="accent-fp-600 w-4 h-4 mt-0.5">
          <span class="min-w-0">
            <b class="text-[13.5px]">Verificar identidad con el padrón en el primer acceso</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">Antes de crear su PIN personal, la persona escribe su fecha de nacimiento y el municipio donde vota; se contrastan con el padrón. Tres fallos: bloqueo definitivo.</span>
          </span>
        </label>

        <label class="flex items-start gap-2.5 rounded-xl border p-3" :class="'border-fp-400 bg-fp-25'">
          <span class="w-4 h-4 mt-0.5 shrink-0 text-fp-700 text-center leading-4">⏱</span>
          <span class="min-w-0">
            <b class="text-[13.5px]">PIN inicial de un solo uso: vence a las <input type="number" min="1" max="720" v-model.number="cfgSeg.pin_caduca_horas" class="inp !inline-block !w-16 !py-0.5 !px-1.5 text-center mx-1"> horas</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">Si no se usó a tiempo, el acceso pide uno nuevo. Regenerar un PIN reinicia el plazo.</span>
          </span>
        </label>

        <label class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer" :class="cfgSeg.confirmar_sne ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
          <input type="checkbox" v-model="cfgSeg.confirmar_sne" class="accent-fp-600 w-4 h-4 mt-0.5">
          <span class="min-w-0">
            <b class="text-[13.5px]">Confirmación de la SNE tras el primer ingreso</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">Cada primer ingreso aparece en «Primeros ingresos por confirmar» con fecha, hora y dispositivo. Hasta que la administración confirme, la persona consulta pero no registra.</span>
          </span>
        </label>
      </div>

      <div class="flex items-center gap-3 mt-4">
        <button class="btn-p btn-s" :disabled="segBusy" @click="guardarCfgSeg">{{ segBusy ? 'Guardando…' : 'Guardar seguridad del acceso' }}</button>
        <span v-if="cfgSeg.actualizado_por" class="text-[11px] text-mut">Última modificación por {{ cfgSeg.actualizado_por }}</span>
      </div>
    </section>

    <!-- ══ Traslados: hasta dónde puede moverse un postulante ══ -->
    <section id="config-traslados" class="card p-4 scroll-mt-20">
      <h3 class="font-serif text-[15px] font-bold mb-1">Traslados y asignación de colegio</h3>
      <p class="text-[12px] text-mut mb-4 max-w-[76ch]">
        Cada postulante tiene dos territorios: dónde vota, que es un dato de la Junta y no cambia, y dónde
        trabajará, que decide el partido. Aquí se define hasta dónde puede moverse una persona respecto al
        colegio donde vota.
      </p>

      <div class="grid gap-2 sm:grid-cols-2">
        <label v-for="(txt, k) in alcanceLbl" :key="k"
               class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer transition-colors"
               :class="cfgTr.alcance === k ? 'border-fp-400 bg-fp-25' : 'border-line bg-white hover:border-fp-200'">
          <input type="radio" :value="k" v-model="cfgTr.alcance" class="accent-fp-600 w-4 h-4 mt-0.5" @change="guardarCfgTr">
          <span class="min-w-0">
            <b class="text-[13.5px]">{{ txt }}</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">
              {{ {
                colegio:   'Nadie trabaja fuera de donde vota. El más estricto: cada delegado conoce su mesa y sus vecinos.',
                municipio: 'Puede cubrir otro colegio de su misma demarcación. Útil donde sobra gente en un recinto y falta en otro.',
                provincia: 'Traslados entre municipios de la misma provincia sin trámite. Equilibra cobertura y arraigo local.',
                libre:     'Sin restricción territorial. Todo queda registrado igualmente.'
              }[k] }}
            </span>
          </span>
        </label>
      </div>

      <div class="mt-4 pt-3 border-t border-line">
        <p class="text-[13.5px] font-semibold mb-1">Colegio donde trabajará</p>
        <p class="text-[11.5px] text-mut mb-2.5 max-w-[74ch]">
          Cada postulante cuenta para un colegio concreto. Cuando vota en el territorio donde se le
          registra, el sistema se lo asigna solo. Aquí se decide cuándo pedirle al encargado que elija.
        </p>
        <select v-model="cfgTr.modo_asignacion" class="inp !py-2 text-[13px] max-w-[420px]" @change="guardarCfgTr">
          <option value="automatico">Automático · no pregunta nunca</option>
          <option value="si_difiere">Preguntar solo si la persona vota fuera · recomendado</option>
          <option value="siempre">Preguntar en cada registro</option>
        </select>
        <p class="text-[11px] text-mut mt-1.5 leading-snug">
          {{ {
            automatico: 'Quien vote fuera del territorio quedará sin colegio asignado y no contará para ninguna mesa. Úsalo solo si la asignación se hará después.',
            si_difiere: 'El trabajo diario no cambia: la mayoría se asigna sola. Solo se pide colegio cuando la persona viene de otra demarcación.',
            siempre:    'Permite repartir gente entre colegios del mismo municipio. Añade un paso a cada registro.'
          }[cfgTr.modo_asignacion] }}
        </p>
      </div>

      <div class="mt-4 pt-3 border-t border-line">
        <p class="text-[13.5px] font-semibold mb-1">Cuando un registro excede el alcance</p>
        <p class="text-[11.5px] text-mut mb-2.5 max-w-[74ch]">Solo la administración de la SNE llega a este punto, porque el encargado no puede registrar fuera de su municipio.</p>
        <div class="grid gap-2 sm:grid-cols-3">
          <label v-for="(txt, k) in { permitir: 'Permitir sin trámite', autorizar: 'Requiere autorización de la SNE', bloquear: 'Bloquear el registro' }" :key="k"
                 class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer transition-colors"
                 :class="cfgTr.excede_accion === k ? 'border-fp-400 bg-fp-25' : 'border-line bg-white hover:border-fp-200'">
            <input type="radio" :value="k" v-model="cfgTr.excede_accion" class="accent-fp-600 w-4 h-4 mt-0.5" @change="guardarCfgTr">
            <span class="min-w-0">
              <b class="text-[13px]">{{ txt }}</b>
              <span class="block text-[11px] text-mut leading-snug mt-0.5">
                {{ {
                  permitir:  'Se registra y cuenta de inmediato. Queda constancia del traslado.',
                  autorizar: 'Se registra como pendiente, no cuenta para ningún colegio, y espera aprobación en Dirigencia → Traslados.',
                  bloquear:  'No se puede registrar: el sistema avisa que la persona debe registrarse en su mismo territorio.'
                }[k] }}
              </span>
            </span>
          </label>
        </div>
      </div>

      <label class="flex items-start gap-2.5 rounded-xl border p-3 mt-3 cursor-pointer transition-colors"
             :class="cfgTr.encargado_solo_municipio ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
        <input type="checkbox" v-model="cfgTr.encargado_solo_municipio" class="accent-fp-600 w-4 h-4 mt-0.5" @change="guardarCfgTr">
        <span>
          <b class="text-[13.5px]">Los encargados electorales solo registran a quien vota en su municipio</b>
          <span class="block text-[11.5px] text-mut leading-snug mt-0.5">
            Activado (recomendado): si la cédula vota en otro municipio, el encargado recibe un aviso y no puede continuar; la base de datos también lo rechaza.
            Desactivado: al encargado le aplican las mismas reglas de alcance que a la administración.
          </span>
        </span>
      </label>

      <p v-if="cfgTr.actualizado_por" class="text-[11px] text-mut mt-2.5">
        Última modificación por {{ cfgTr.actualizado_por }}
      </p>
      <p v-if="cfgBusy" class="text-[11px] text-fp-700 mt-2">Guardando…</p>
    </section>

    <!-- ══ Marca de agua por documento ══ -->
    <section id="config-sello" class="card p-4 scroll-mt-20">
      <h3 class="font-serif text-[15px] font-bold mb-1">Marca de agua en los documentos</h3>
      <p class="text-[12px] text-mut mb-4 max-w-[76ch]">
        La marca existe para rastrear fugas: si un listado con nombres y cédulas circula donde no debe,
        indica quién lo imprimió y cuándo. En documentos sin datos personales no cumple esa función.
        La emisión queda registrada en la bitácora aunque el documento salga sin marca.
      </p>

      <div class="space-y-2">
        <label v-for="d in docs" :key="d.k"
               class="flex items-start gap-3 rounded-xl border p-3 cursor-pointer transition-colors"
               :class="cfgDoc[d.k] ? 'border-fp-300 bg-fp-25' : 'border-line bg-white'">
          <input type="checkbox" :checked="!!cfgDoc[d.k]" class="accent-fp-600 w-4 h-4 mt-0.5"
                 @change="guardarCfgDoc(d.k, $event.target.checked)">
          <span class="min-w-0">
            <b class="text-[13.5px]">{{ d.t }}</b>
            <span class="text-[11.5px] ml-2" :class="cfgDoc[d.k] ? 'text-fp-700' : 'text-mut'">
              {{ cfgDoc[d.k] ? 'con marca' : 'sin marca' }}
            </span>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">{{ d.d }}</span>
          </span>
        </label>
      </div>

      <p v-if="cfgDoc.actualizado_por" class="text-[11px] text-mut mt-2.5">
        Última modificación por {{ cfgDoc.actualizado_por }}
      </p>
    </section>


    <!-- ══ Formularios habilitados (fase 69) ══ -->
    <section id="config-formularios" class="card p-4 scroll-mt-20">
      <h3 class="font-serif text-[15px] font-bold mb-1">Formularios habilitados</h3>
      <p class="text-[12px] text-mut mb-3 max-w-[76ch]">Si un formulario está deshabilitado, sus botones desaparecen y la base de datos rechaza la impresión aunque alguien intente forzarla.</p>
      <div class="grid gap-2 sm:grid-cols-2">
        <label v-for="f in [['permitir_individual','Formulario individual (lleno)','El que se imprime tras registrar, con los datos del postulante, para las firmas.'],['permitir_blanco','Formulario en blanco','Sin datos, para repartir y llenar a mano.']]" :key="f[0]"
               class="flex items-start gap-2.5 rounded-xl border p-3 cursor-pointer transition-colors"
               :class="cfgDoc[f[0]] !== false ? 'border-fp-400 bg-fp-25' : 'border-line bg-white'">
          <input type="checkbox" :checked="cfgDoc[f[0]] !== false" class="accent-fp-600 w-4 h-4 mt-0.5"
                 @change="guardarCfgDoc(f[0], $event.target.checked)">
          <span class="min-w-0">
            <b class="text-[13.5px]">{{ f[1] }}</b>
            <span class="block text-[11.5px] text-mut leading-snug mt-0.5">{{ f[2] }} · {{ cfgDoc[f[0]] !== false ? 'Habilitado' : 'Deshabilitado' }}</span>
          </span>
        </label>
      </div>
    </section>

    <section id="permisos-rol" class="card p-4 scroll-mt-20">
      <div class="flex flex-wrap items-baseline gap-2 mb-1">
        <h3 class="font-serif text-[15px] font-bold mr-auto">Qué ve y qué imprime cada rol</h3>
        <button class="btn-o btn-s" @click="cargarPermRol">Actualizar</button>
      </div>
      <p class="text-[12px] text-mut mb-3 max-w-[76ch]">
        La estructura de delegados es información sensible: un listado con nombres y teléfonos
        permitiría contactar individualmente a cada dirigente. Por norma solo la administración
        ve cédulas y teléfonos completos; los demás roles ven el dato enmascarado y cada
        revelación queda registrada. Estas reglas se aplican en el servidor, no en la pantalla.
      </p>

      <div class="overflow-x-auto">
        <table class="w-full min-w-[820px]">
          <thead class="bg-paper border-b border-line"><tr>
            <th class="th">Rol</th>
            <th class="th text-center" colspan="3">Datos que ve</th>
            <th class="th text-center" colspan="3">Documentos que imprime</th>
          </tr>
          <tr class="text-[11px] text-mut">
            <th class="px-3 pb-1.5"></th>
            <th class="px-2 pb-1.5 font-normal text-center">Nombres</th>
            <th class="px-2 pb-1.5 font-normal text-center">Cédula</th>
            <th class="px-2 pb-1.5 font-normal text-center">Teléfono</th>
            <th class="px-2 pb-1.5 font-normal text-center">Individual</th>
            <th class="px-2 pb-1.5 font-normal text-center">Relación</th>
            <th class="px-2 pb-1.5 font-normal text-center">Validación</th>
          </tr></thead>
          <tbody>
            <tr v-for="r in permRol" :key="r.rol" class="border-b border-line/60">
              <td class="td font-semibold whitespace-nowrap">{{ rolLbl[r.rol] || r.rol }}</td>
              <td v-for="c in ['ver_nombres','ver_cedula','ver_telefono','imprimir_individual','imprimir_relacion','imprimir_validacion']"
                  :key="c" class="td text-center">
                <input type="checkbox" class="accent-fp-600 w-4 h-4 cursor-pointer"
                       :checked="r[c]" :disabled="permBusy || r.rol === 'admin_sne'"
                       :title="r.rol === 'admin_sne' ? 'La administración conserva acceso completo' : ''"
                       @change="guardarPermRol(r, c, $event.target.checked)">
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-[11px] text-mut mt-2.5">
        La administración de la SNE conserva acceso completo y no puede limitarse desde aquí,
        para que nunca quede el sistema sin nadie capaz de operarlo.
      </p>
    </section>
    </template>

  </section>
</template>
