/* src/stores/print.js */
import { ref, nextTick } from 'vue';
import { perfil } from './auth';
import { sb } from '../lib/supabase';
import { t } from './toasts';
import { catMap } from './catalogo';

/* Trabajo de impresión activo: { tipo: 'individual'|'blanco'|'relacion', p, rows, mun, off } */
export const printJob = ref(null);
export const printBusy = ref(false);
export const printSello = ref(null);
/* Cierto cuando el documento se imprime sin marca por configuración */
export const selloOmitido = ref(false);

/* Registra el documento en la bitácora y devuelve el sello de trazabilidad */
export async function sellarImpresion(tipo, territorio, registros) {
  const { data, error } = await sb.rpc('portal_log_impresion', {
    p_tipo: tipo, p_territorio: territorio ?? null, p_registros: registros ?? null
  });
  if (error) { printSello.value = null; return { ok: false, msg: error.message }; }
  printSello.value = (data.sella === false) ? null : { nombre: data.nombre, momento: new Date(data.momento) };
  selloOmitido.value = data.sella === false;
  return { ok: true };
}

const officialsCache = new Map();

/** Autoridades firmantes del municipio (presidente, secretario general, encargado electoral). */
export async function cargarOficiales(munId) {
  if (!munId) return {};
  if (officialsCache.has(munId)) return officialsCache.get(munId);
  const { data } = await sb.from('usuarios_territoriales')
    .select('nombre,rol').eq('municipio_id', munId).eq('activo', true)
    .in('rol', ['presidente','secretario_general','enc_electoral']);
  const off = {};
  (data || []).forEach(u => { if (!off[u.rol]) off[u.rol] = u.nombre; });
  officialsCache.set(munId, off);
  return off;
}

export const munObjDe = id =>
  catMap.value.get(id) ||
  (perfil.value?.municipio_id === id ? { nombre: perfil.value.municipio, provincia_nombre: perfil.value.provincia, macroregion: perfil.value.region } : null);

export async function printIndividual(row) {
  const nom = `${row.nombres || ''} ${row.apellido1 || ''}`.trim();
  const s = await sellarImpresion('Formulario individual', nom, 1);
  if (!s.ok) { t(s.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  const off = await cargarOficiales(row.municipio_id);
  printJob.value = { tipo: 'individual', p: row, mun: munObjDe(row.municipio_id), off };
}

export async function printBlanco(munId) {
  const s = await sellarImpresion('Formulario en blanco', munObjDe(munId)?.nombre || '', 0);
  if (!s.ok) { t(s.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  const off = munId ? await cargarOficiales(munId) : {};
  printJob.value = { tipo: 'blanco', p: null, mun: munId ? munObjDe(munId) : null, off };
}

export async function printRelacion(rows, munId) {
  const s = await sellarImpresion('Relación de postulantes', munObjDe(munId)?.nombre || '', (rows || []).length);
  if (!s.ok) { t(s.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  const off = munId ? await cargarOficiales(munId) : {};
  printJob.value = { tipo: 'relacion', rows, mun: munId ? munObjDe(munId) : null, off };
}

/** Reporte de validación: todos los colegios del municipio con sus postulantes. */
export async function printCobertura(munId, jceId, circId) {
  if (!munId) return;
  if (!printSello.value) {
    const s = await sellarImpresion('Reporte para validación', munObjDe(munId)?.nombre || '', null);
    if (!s.ok) { t(s.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  }
  printBusy.value = true;
  const [cobRes, off] = await Promise.all([
    sb.rpc('portal_cobertura_colegios', {
      p_municipio: munId, p_jce: jceId || null, p_circ: circId || null
    }),
    cargarOficiales(munId)
  ]);
  const cob = cobRes.data || [];
  /* Solo los postulantes de los colegios que quedaron en el alcance */
  const ids = [...new Set(cob.map(c => c.id_colegio).filter(Boolean))];
  let personas = [];
  if (ids.length) {
    const r = await sb.from('postulantes_2028')
      .select('numero_formulario,cedula,nombres,apellido1,apellido2,cargo_postulado,telefono,estado,id_colegio_padron')
      .eq('municipio_id', munId)
      .in('id_colegio_padron', ids)
      .not('estado', 'in', '(rechazado,no_aprobado)')
      .order('id_colegio_padron').order('cargo_postulado');
    personas = r.data || [];
  }
  const porColegio = new Map();
  personas.forEach(p => {
    const k = p.id_colegio_padron;
    if (!porColegio.has(k)) porColegio.set(k, []);
    porColegio.get(k).push(p);
  });
  printJob.value = {
    tipo: 'colegios', mun: munObjDe(munId), cob, porColegio, off,
    alcance: alcanceTexto(cob, jceId, circId)
  };
  printBusy.value = false;
}

/* Describe el alcance impreso: distrito y circunscripción cuando los hay */
function alcanceTexto(cob, jceId, circId) {
  const p = [];
  if (jceId) {
    const d = cob.find(c => c.jce_id === jceId);
    p.push(d?.distrito ? `Distrito ${d.distrito}` : 'Distrito seleccionado');
  }
  if (circId) {
    const c = cob.find(x => x.circ_id === circId);
    p.push(c?.circ_nombre || `Circunscripción ${circId}`);
  }
  return p.join(' · ');
}

/** Formulario General del Territorio: resumen firmable + relación completa. */
export async function printResumen(munId, jceId, circId) {
  if (!munId) return;
  if (!printSello.value) {
    const s = await sellarImpresion('Formulario general del territorio', munObjDe(munId)?.nombre || '', null);
    if (!s.ok) { t(s.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  }
  printBusy.value = true;
  const [cobRes, off] = await Promise.all([
    sb.rpc('portal_cobertura_colegios', {
      p_municipio: munId, p_jce: jceId || null, p_circ: circId || null
    }),
    cargarOficiales(munId)
  ]);
  const cob = cobRes.data || [];

  /* Solo las personas de los colegios que quedaron dentro del alcance */
  const ids = [...new Set(cob.map(c => c.id_colegio).filter(Boolean))];
  let pers = [];
  if (ids.length) {
    const r = await sb.from('postulantes_2028')
      .select('numero_formulario,cedula,nombres,apellido1,apellido2,cargo_postulado,telefono,estado,codigo_colegio,id_colegio_padron')
      .eq('municipio_id', munId)
      .in('id_colegio_padron', ids)
      .not('estado', 'in', '(rechazado,no_aprobado)')
      .order('numero_formulario');
    pers = r.data || [];
  }
  const distDe = new Map(cob.map(c => [c.id_colegio, c.distrito]));
  const tot = { t: 0, s: 0, o: 0, i: 0 };
  pers.forEach(p => {
    if (p.cargo_postulado === 'delegado_titular') tot.t++;
    else if (p.cargo_postulado === 'suplente_delegado') tot.s++;
    else if (p.cargo_postulado === 'observador_escrutinio') tot.o++;
    else tot.i++;
  });
  const colTot = cob.length,
        colOk  = cob.filter(c => c.personas >= 3).length,
        colPar = cob.filter(c => c.personas > 0 && c.personas < 3).length;
  printJob.value = { tipo: 'resumen', mun: munObjDe(munId), pers, distDe, tot,
                     colTot, colOk, colPar, colVac: colTot - colOk - colPar, off,
                     alcance: alcanceTexto(cob, jceId, circId) };
  printBusy.value = false;
}

export function cerrarPrint() { printJob.value = null; printSello.value = null; }
export function doPrint() { nextTick(() => window.print()); }
