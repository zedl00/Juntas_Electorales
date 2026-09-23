<!-- src/views/PostulantesView.vue -->
<script setup>
/* ── Enmascarado de datos de contacto ── */
const revelados = ref(new Set());

const maskTel = (t, id) => {
  const d = String(t || '').replace(/\D/g, '');
  if (!d) return '';
  if (permisos.value.ver_telefono || revelados.value.has(id))
    return d.length === 10 ? `${d.slice(0,3)}-${d.slice(3,6)}-${d.slice(6)}` : d;
  return `${d.slice(0,3)}-•••-••${d.slice(-2)}`;
};

const maskCed = (c, id) => {
  const d = String(c || '').replace(/\D/g, '');
  if (!d) return '';
  if (permisos.value.ver_cedula || revelados.value.has(id))
    return d.length === 11 ? `${d.slice(0,3)}-${d.slice(3,10)}-${d.slice(10)}` : d;
  return `${d.slice(0,3)}-•••••••-${d.slice(-1)}`;
};

const oculto = (id) => !permisos.value.ver_telefono && !revelados.value.has(id);

const revelar = async (row) => {
  const { data, error } = await sb.rpc('portal_revelar_contacto', { p_postulante: row.id });
  if (error) { t('No se pudo revelar: ' + error.message, 'err'); return; }
  if (!data?.ok) { t(data?.msg || 'Sin autorización.', 'err'); return; }
  revelados.value = new Set([...revelados.value, row.id]);
  t('Dato revelado · queda registrado en la bitácora', 'ok');
};

import { ref, reactive, computed, watch, onMounted, onActivated } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { sb } from '../lib/supabase';
import { perfil, esAdmin, scopeAmplio, canRegister, permisos, velo } from '../stores/auth';
import { regiones, provsOf, munsOf, nombreMun } from '../stores/catalogo';
import { cargarKpi, cargarTerr } from '../stores/kpi';
import { printIndividual, printRelacion, printBusy, docsCfg } from '../stores/print';
import { cargoLbl, cargoCorto, estadoLbl, estadoCls, nivelOpts } from '../lib/constantes';
import { fmt, fmtCed, soloDig, edad, fecha, fechaHora } from '../lib/formato';
import { t } from '../stores/toasts';

defineOptions({ name: 'PostulantesView' });
const route = useRoute();
const router = useRouter();

/* ── Listado ── */
const rows = ref([]), pTotal = ref(0), pBusy = ref(false), csvBusy = ref(false);
const page = ref(0), pageSize = ref(50);
const pSort = reactive({ c: 'created_at', asc: false });
const f = reactive({ q: '', estado: '', cargo: '', sexo: '', exp: '', region: '', prov: '', mun: 0, firme: '' });

const buildQ = (sel, withCount) => {
  let q = sb.from('postulantes_2028').select(sel, withCount ? { count: 'exact' } : undefined);
  const s = f.q.trim().replace(/[,()]/g, ' ').trim();
  if (s) {
    const dg = soloDig(s);
    const parts = ['nombres.ilike.%' + s + '%', 'apellido1.ilike.%' + s + '%', 'apellido2.ilike.%' + s + '%'];
    if (dg.length >= 4) parts.push('cedula.ilike.%' + dg + '%');
    q = q.or(parts.join(','));
  }
  if (f.estado) q = q.eq('estado', f.estado);
  if (f.cargo)  q = q.eq('cargo_postulado', f.cargo);
  if (f.sexo)   q = q.eq('sexo', f.sexo);
  if (f.exp === 'si')   q = q.or('experiencia_2020.eq.true,experiencia_2024.eq.true');
  if (f.exp === 'no')   q = q.eq('experiencia_2020', false).eq('experiencia_2024', false);
  if (f.exp === '2020') q = q.eq('experiencia_2020', true);
  if (f.exp === '2024') q = q.eq('experiencia_2024', true);
  if (f.firme === 'si') q = q.eq('candidato_firme', true);
  if (f.firme === 'no') q = q.eq('candidato_firme', false);
  if (f.region) q = q.eq('macroregion', f.region);
  if (f.prov)   q = q.eq('provincia_id', f.prov);
  if (f.mun)    q = q.eq('municipio_id', f.mun);
  return q;
};

const cargarPost = async () => {
  pBusy.value = true;
  const { data, count, error } = await buildQ('*', true)
    .order(pSort.c, { ascending: pSort.asc })
    .range(page.value * pageSize.value, (page.value + 1) * pageSize.value - 1);
  pBusy.value = false;
  if (error) { t('Error cargando postulantes: ' + error.message, 'err'); return; }
  rows.value = data || []; pTotal.value = count || 0;
};

const sortP = c => {
  if (pSort.c === c) pSort.asc = !pSort.asc;
  else { pSort.c = c; pSort.asc = !['created_at', 'id'].includes(c); }
  page.value = 0; cargarPost();
};
const pArrow = c => pSort.c === c ? (pSort.asc ? '▲' : '▼') : '';
const aplicarF = () => { page.value = 0; cargarPost(); };
const limpiarF = () => { Object.assign(f, { q: '', estado: '', cargo: '', sexo: '', exp: '', region: '', prov: '', mun: 0 }); aplicarF(); };

/* Paginación completa (evita el tope silencioso de 1000 filas de Supabase) */
const fetchTodo = async () => {
  const all = []; let i = 0;
  while (true) {
    const { data, error } = await buildQ('*').order(pSort.c, { ascending: pSort.asc }).range(i * 1000, (i + 1) * 1000 - 1);
    if (error) { t('Error exportando: ' + error.message, 'err'); return null; }
    all.push(...(data || []));
    if (!data || data.length < 1000) break;
    i++;
  }
  return all;
};

const exportCSV = async () => {
  csvBusy.value = true;
  const all = await fetchTodo();
  csvBusy.value = false;
  if (!all) return;
  const esc = v => '"' + String(v ?? '').replace(/"/g, '""') + '"';
  const head = ['Folio','Cédula','Nombres','Apellidos','Sexo','F. Nacimiento','Teléfono','WhatsApp','Correo','Dirección','Nivel','Ocupación','Vínculo FP','Cargo','Colegio','Recinto','Circunscripción','Municipio','Región','Exp. 2024','Etapa','Notas','Registrado'];
  const lines = all.map(r => [
    r.numero_formulario, fmtCed(r.cedula), r.nombres, (r.apellido1 + ' ' + (r.apellido2 || '')).trim(), r.sexo, r.fecha_nacimiento,
    r.telefono, r.whatsapp, r.email, r.direccion, r.nivel_academico, r.ocupacion, r.militancia, cargoLbl[r.cargo_postulado] || r.cargo_postulado,
    (r.codigo_colegio || r.id_colegio_padron || ''), r.recinto_nombre, r.circunscripcion, nombreMun(r.municipio_id), r.macroregion,
    r.experiencia_2020 ? 'Sí' : 'No', r.experiencia_2024 ? 'Sí' : 'No', r.candidato_firme ? 'Sí' : 'No', estadoLbl[r.estado] || r.estado, r.notas, fechaHora(r.created_at)
  ].map(esc).join(','));
  const csv = '\uFEFF' + head.map(esc).join(',') + '\n' + lines.join('\n');
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a'); a.href = url; a.download = 'postulantes_2028.csv'; a.click(); URL.revokeObjectURL(url);
  t(fmt(all.length) + ' postulantes exportados', 'ok');
};

const imprimirRelacion = async () => {
  printBusy.value = true;
  const all = await fetchTodo();
  if (!all) { printBusy.value = false; return; }
  const mid = f.mun || (!scopeAmplio.value ? (perfil.value?.municipio_id || 0) : 0);
  await printRelacion(all, mid);
  printBusy.value = false;
};

/* ── Detalle / edición ── */
const det = ref(null), detEdit = ref(false), dF = ref({}), detBusy = ref(false), detBit = ref([]);
const estadoSel = ref(''), estadoNota = ref('');

const canEditRow = r => !!r && (esAdmin.value || (perfil.value?.rol === 'enc_electoral' && r.municipio_id === perfil.value.municipio_id && ['postulado','devuelto'].includes(r.estado)));

const abrirDet = async r => {
  det.value = r;
  cargarFF(r.id); detEdit.value = false; estadoSel.value = ''; estadoNota.value = ''; detBit.value = [];
  if (esAdmin.value) {
    const { data } = await sb.from('postulantes_bitacora').select('*').eq('postulante_id', r.id).order('created_at', { ascending: false }).limit(8);
    detBit.value = data || [];
  }
};
/* ── Formularios firmados escaneados ── */
const ffs = ref([]), ffBusy = ref(false), ffErr = ref('');

const sha256 = async (file) => {
  const buf = await file.arrayBuffer();
  const h = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(h)).map(b => b.toString(16).padStart(2, '0')).join('');
};

const cargarFF = async (id) => {
  ffs.value = [];
  if (!id) return;
  const { data } = await sb.from('formularios_firmados')
    .select('*').eq('postulante_id', id).order('subido_at', { ascending: false });
  ffs.value = data || [];
};

const subirFF = async (ev) => {
  const file = ev.target.files?.[0];
  if (!file || !det.value) return;
  if (file.size > 12 * 1024 * 1024) { ffErr.value = 'El archivo supera los 12 MB. Reduce la calidad del escaneo.'; return; }
  ffBusy.value = true; ffErr.value = '';
  try {
    const hash = await sha256(file);
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
    const ruta = `${det.value.municipio_id}/${det.value.numero_formulario}/${Date.now()}.${ext}`;
    const up = await sb.storage.from('formularios').upload(ruta, file, { upsert: false });
    if (up.error) throw up.error;
    const { error } = await sb.rpc('portal_formulario_registrar', {
      p_postulante: det.value.id, p_ruta: ruta, p_hash: hash,
      p_tipo: 'individual', p_nombre: file.name, p_tamano: file.size, p_paginas: 1
    });
    if (error) throw error;
    t('Formulario recibido', 'ok');
    cargarFF(det.value.id);
  } catch (e) {
    ffErr.value = e.message || 'No se pudo subir el archivo.';
  }
  ffBusy.value = false;
  ev.target.value = '';
};

const verFF = async (f) => {
  const { data } = await sb.storage.from('formularios').createSignedUrl(f.ruta, 300);
  if (data?.signedUrl) window.open(data.signedUrl, '_blank');
};

const estadoFF = async (f, estado) => {
  const { error } = await sb.rpc('portal_formulario_estado', { p_id: f.id, p_estado: estado, p_nota: null });
  if (error) { t(error.message, 'err'); return; }
  t(estado === 'verificado' ? 'Formulario verificado' : 'Formulario observado', 'ok');
  cargarFF(det.value.id);
};

const cerrarDet = () => { det.value = null; detEdit.value = false; };

const iniciarEdit = () => {
  const r = det.value;
  dF.value = { telefono: r.telefono || '', whatsapp: r.whatsapp || '', email: r.email || '', direccion: r.direccion || '', nivel_academico: r.nivel_academico || '', ocupacion: r.ocupacion || '', militancia: r.militancia || '', cargo_postulado: r.cargo_postulado, experiencia_detalle: r.experiencia_detalle || '', experiencia_2020: !!r.experiencia_2020, experiencia_2024: !!r.experiencia_2024, candidato_firme: !!r.candidato_firme, notas: r.notas || '' };
  detEdit.value = true;
};

const syncRow = nuevo => { det.value = nuevo; const i = rows.value.findIndex(x => x.id === nuevo.id); if (i >= 0) rows.value[i] = nuevo; };

const guardarDet = async () => {
  detBusy.value = true;
  const { data, error } = await sb.from('postulantes_2028').update({ ...dF.value }).eq('id', det.value.id).select().single();
  detBusy.value = false;
  if (error) { t('No se pudo guardar: ' + error.message, 'err'); return; }
  syncRow(data); detEdit.value = false; t('Cambios guardados', 'ok');
};

const setEstado = async nuevo => {
  if (!nuevo) return;
  if (['devuelto','rechazado'].includes(nuevo) && !estadoNota.value.trim()) { t('Escribe la nota: es obligatoria al devolver o rechazar.', 'err'); return; }
  detBusy.value = true;
  const upd = { estado: nuevo };
  if (nuevo === 'validado') upd.validado_por = perfil.value.id;
  if (estadoNota.value.trim()) upd.notas = (det.value.notas ? det.value.notas + '\n' : '') + '[' + new Date().toLocaleDateString('es-DO') + '] ' + (estadoLbl[nuevo] || nuevo) + ': ' + estadoNota.value.trim();
  const { data, error } = await sb.from('postulantes_2028').update(upd).eq('id', det.value.id).select().single();
  detBusy.value = false;
  if (error) { t('No se pudo actualizar la etapa: ' + error.message, 'err'); return; }
  syncRow(data); estadoNota.value = ''; estadoSel.value = '';
  t('Etapa actualizada a ' + (estadoLbl[nuevo] || nuevo), 'ok');
  cargarKpi(); if (scopeAmplio.value) cargarTerr();
};

/* ── Filtro por territorio llegado desde Inicio (?mun=ID) ── */
watch(() => route.query.mun, mun => {
  if (route.name !== 'postulantes') return;
  const id = Number(mun || 0);
  if (id && id !== f.mun) { Object.assign(f, { q: '', estado: '', cargo: '', sexo: '', exp: '', region: '', prov: '', mun: id }); aplicarF(); }
}, { immediate: true });

onMounted(cargarPost);
onActivated(() => { if (!route.query.mun) cargarPost(); });
</script>

<template>
  <section class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <h2 class="mr-auto font-serif text-xl font-bold">Postulantes</h2>
      <RouterLink to="/idoneidad" class="btn-o btn-s">◈ Análisis de idoneidad</RouterLink>
      <div class="flex gap-2">
        <button class="btn-o btn-s" @click="imprimirRelacion" :disabled="printBusy || !pTotal">⎙ Relación</button>
        <button class="btn-o btn-s" @click="exportCSV" :disabled="csvBusy || !pTotal">{{ csvBusy ? 'Exportando…' : '⇩ CSV' }}</button>
        <button v-if="canRegister" class="btn-p btn-s" @click="router.push('/registrar')">+ Registrar</button>
      </div>
    </div>

    <div class="card p-3.5">
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
        <input v-model="f.q" class="inp !py-2 text-[12.5px] col-span-2 sm:col-span-1" placeholder="Cédula o nombre…" @keyup.enter="aplicarF">
        <select v-model="f.estado" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option value="">Etapa: todas</option><option v-for="(l, k) in estadoLbl" :key="k" :value="k">{{ l }}</option></select>
        <select v-model="f.cargo" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option value="">Cargo: todos</option><option v-for="(l, k) in cargoLbl" :key="k" :value="k">{{ l }}</option></select>
        <select v-model="f.sexo" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option value="">Sexo: todos</option><option value="M">Masculino</option><option value="F">Femenino</option></select>
        <select v-model="f.exp" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option value="">Experiencia: todos</option><option value="si">Con experiencia</option><option value="2020">Solo 2020</option><option value="2024">Solo 2024</option><option value="no">Sin experiencia</option></select>
        <select v-model="f.firme" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option value="">Firma: todos</option><option value="si">★ Firmados</option><option value="no">Pendientes de firma</option></select>
        <button class="btn-o btn-s" @click="limpiarF">Limpiar</button>
      </div>
      <div v-if="scopeAmplio" class="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-2 pt-2 border-t border-line/70">
        <select v-if="esAdmin" v-model="f.region" class="inp !py-2 text-[12.5px]" @change="f.prov=''; f.mun=0; aplicarF()"><option value="">Región: todas</option><option v-for="r in regiones" :key="r" :value="r">{{ r }}</option></select>
        <select v-model.number="f.prov" class="inp !py-2 text-[12.5px]" @change="f.mun=0; aplicarF()"><option value="">Provincia: todas</option><option v-for="p in provsOf(f.region)" :key="p.id" :value="p.id">{{ p.nombre }}</option></select>
        <select v-model.number="f.mun" class="inp !py-2 text-[12.5px]" @change="aplicarF"><option :value="0">Municipio: todos</option><option v-for="m in munsOf(f.region, f.prov)" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}</option></select>
      </div>
    </div>

    <div class="card overflow-hidden">
      <div class="overflow-x-auto velo-datos" :data-velo="velo">
        <table class="w-full min-w-[860px]">
          <thead class="bg-paper border-b border-line">
            <tr>
              <th class="th cursor-pointer" @click="sortP('numero_formulario')">Folio {{ pArrow('numero_formulario') }}</th>
              <th class="th cursor-pointer" @click="sortP('cedula')">Cédula {{ pArrow('cedula') }}</th>
              <th class="th cursor-pointer" @click="sortP('apellido1')">Nombre {{ pArrow('apellido1') }}</th>
              <th class="th cursor-pointer" @click="sortP('sexo')">Sexo {{ pArrow('sexo') }}</th>
              <th class="th cursor-pointer" @click="sortP('cargo_postulado')">Cargo {{ pArrow('cargo_postulado') }}</th>
              <th class="th cursor-pointer" @click="sortP('id_colegio_padron')">Colegio {{ pArrow('id_colegio_padron') }}</th>
              <th v-if="scopeAmplio" class="th cursor-pointer" @click="sortP('municipio_id')">Territorio {{ pArrow('municipio_id') }}</th>
              <th class="th cursor-pointer" @click="sortP('estado')">Etapa {{ pArrow('estado') }}</th>
              <th class="th cursor-pointer" @click="sortP('created_at')">Fecha {{ pArrow('created_at') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rows" :key="r.id" class="border-b border-line/70 hover:bg-fp-25/60 cursor-pointer" @click="abrirDet(r)">
              <td class="td font-mono text-[12px] font-semibold whitespace-nowrap">{{ r.numero_formulario }}</td>
              <td class="td whitespace-nowrap tabular-nums" :class="oculto(r.id) ? 'text-mut' : ''">{{ maskCed(r.cedula, r.id) }}</td>
              <td class="td font-semibold whitespace-nowrap">{{ r.nombres }} {{ r.apellido1 }} {{ r.apellido2 || '' }}<span v-if="r.experiencia_2020 || r.experiencia_2024" class="text-fp-600" :title="'Experiencia ' + [r.experiencia_2020 ? '2020' : null, r.experiencia_2024 ? '2024' : null].filter(Boolean).join(' y ')"> ✓</span><span v-if="r.candidato_firme" class="text-fp-700 font-bold" title="Firmado"> ★</span></td>
              <td class="td">{{ r.sexo }}</td>
              <td class="td whitespace-nowrap">{{ cargoCorto[r.cargo_postulado] }}</td>
              <td class="td whitespace-nowrap"><span class="tabular-nums">{{ r.codigo_colegio || r.id_colegio_padron || '—' }}</span><span class="block text-[10px] text-mut max-w-[140px] truncate">{{ r.recinto_nombre }}</span></td>
              <td v-if="scopeAmplio" class="td text-mut whitespace-nowrap">{{ nombreMun(r.municipio_id) }}</td>
              <td class="td"><span class="badge" :class="estadoCls[r.estado]">{{ estadoLbl[r.estado] }}</span></td>
              <td class="td text-mut whitespace-nowrap text-[12px]">{{ fecha(r.created_at) }}</td>
            </tr>
            <tr v-if="!rows.length && !pBusy"><td :colspan="scopeAmplio ? 9 : 8" class="td text-center text-mut py-10">Sin postulantes con estos criterios.<span v-if="canRegister"> Registra el primero desde <b>Registrar</b>.</span></td></tr>
            <tr v-if="pBusy"><td :colspan="scopeAmplio ? 9 : 8" class="td text-center text-mut py-10">Cargando…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 border-t border-line flex flex-wrap items-center justify-between gap-2 text-[12px] text-mut">
        <span>{{ fmt(pTotal) }} postulantes · página {{ page + 1 }} de {{ Math.max(1, Math.ceil(pTotal / pageSize)) }}</span>
        <div class="flex items-center gap-2">
          <select v-model.number="pageSize" class="inp !w-auto !py-1 text-[12px]" @change="page=0; cargarPost()"><option :value="25">25</option><option :value="50">50</option><option :value="100">100</option></select>
          <button class="btn-o btn-s" :disabled="page === 0" @click="page--; cargarPost()">←</button>
          <button class="btn-o btn-s" :disabled="(page + 1) * pageSize >= pTotal" @click="page++; cargarPost()">→</button>
        </div>
      </div>
    </div>

    <!-- ═ Modal: detalle / edición ═ -->
    <div v-if="det" class="modal fixed inset-0 z-50 bg-ink/40 p-3 sm:p-6 flex items-start sm:items-center justify-center overflow-y-auto" @click.self="cerrarDet">
      <div class="card w-full max-w-2xl max-h-[92vh] overflow-y-auto">
        <div class="p-4 border-b border-line flex items-start justify-between gap-3 sticky top-0 bg-white rounded-t-2xl">
          <div>
            <div class="text-[10.5px] font-mono font-bold text-fp-700">Nº {{ det.numero_formulario }}</div>
            <div class="font-serif font-bold text-[17px] leading-tight">{{ det.nombres }} {{ det.apellido1 }} {{ det.apellido2 || '' }}</div>
            <div class="text-[11.5px] text-mut">{{ maskCed(det.cedula, det.id) }} · {{ nombreMun(det.municipio_id) }}</div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <span class="badge" :class="estadoCls[det.estado]">{{ estadoLbl[det.estado] }}</span>
            <button class="w-8 h-8 rounded-lg border border-line grid place-items-center text-mut hover:text-ink" @click="cerrarDet">✕</button>
          </div>
        </div>

        <div class="p-4 space-y-4">
          <div v-if="!detEdit" class="grid sm:grid-cols-2 gap-x-4 gap-y-2 text-[13px]">
            <div><span class="text-mut">Sexo · Edad:</span> {{ det.sexo }} · {{ edad(det.fecha_nacimiento) }} años</div>
            <div><span class="text-mut">Cargo:</span> <b>{{ cargoLbl[det.cargo_postulado] }}</b></div>
            <div class="flex items-center gap-2">
              <span><span class="text-mut">Teléfono:</span> {{ det.telefono ? maskTel(det.telefono, det.id) : '—' }}</span>
              <button v-if="det.telefono && oculto(det.id)" class="btn-o !py-0.5 !px-2 text-[11px]" @click="revelar(det)">Revelar</button>
            </div>
            <div><span class="text-mut">WhatsApp:</span> {{ det.whatsapp ? maskTel(det.whatsapp, det.id) : '—' }}</div>
            <div><span class="text-mut">Correo:</span> {{ det.email || '—' }}</div>
            <div><span class="text-mut">Nivel · Ocupación:</span> {{ det.nivel_academico || '—' }} · {{ det.ocupacion || '—' }}</div>
            <div><span class="text-mut">Correo · Vínculo FP:</span> {{ det.email || '—' }} · {{ det.militancia || '—' }}</div>
            <div class="sm:col-span-2"><span class="text-mut">Dirección:</span> {{ det.direccion || '—' }}</div>
            <div class="sm:col-span-2 rounded-xl bg-paper border border-line p-3 text-[12.5px]">
              <b>Colegio {{ det.codigo_colegio || det.id_colegio_padron }}</b> — {{ det.colegio_desc || '' }}<br>
              <span class="text-mut">Recinto:</span> {{ det.recinto_nombre || '—' }} · <span class="text-mut">Circ.:</span> {{ det.circunscripcion || '—' }}
            </div>
            <div class="sm:col-span-2"><span class="text-mut">Experiencia:</span>
              <template v-if="det.experiencia_2020 || det.experiencia_2024">{{ [det.experiencia_2020 ? '2020' : null, det.experiencia_2024 ? '2024' : null].filter(Boolean).join(' y ') }}</template>
              <template v-else>Sin experiencia previa</template>
              <span v-if="det.experiencia_detalle"> — {{ det.experiencia_detalle }}</span></div>
            <div class="sm:col-span-2 pt-2 mt-1 border-t border-line">
              <div class="flex items-center justify-between gap-2 mb-2">
                <span class="text-[11px] font-bold uppercase tracking-wider text-mut">Formulario firmado</span>
                <label class="btn-o btn-s cursor-pointer">
                  {{ ffBusy ? 'Subiendo…' : '⎙ Escanear o subir' }}
                  <input type="file" accept="image/*,application/pdf" capture="environment" class="hidden" :disabled="ffBusy" @change="subirFF">
                </label>
              </div>
              <div v-if="ffErr" class="errbx mb-2">{{ ffErr }}</div>
              <div v-for="f in ffs" :key="f.id" class="flex items-center gap-2 py-1.5 border-b border-line/50 last:border-0">
                <span class="badge" :class="f.estado === 'verificado' ? 'border-fp-600 bg-fp-600 text-white' : (f.estado === 'observado' ? 'border-amber-200 bg-amber-50 text-amber-800' : 'border-line bg-paper text-mut')">
                  {{ f.estado === 'verificado' ? '✓ Verificado' : (f.estado === 'observado' ? 'Observado' : 'Recibido') }}
                </span>
                <span class="text-[12px] text-mut flex-1 truncate">{{ f.nombre_archivo }} · {{ fecha(f.subido_at) }}</span>
                <button class="btn-o btn-s" @click="verFF(f)">Ver</button>
                <template v-if="esAdmin && f.estado !== 'verificado'">
                  <button class="btn-o btn-s" @click="estadoFF(f, 'verificado')">✓</button>
                  <button class="btn-o btn-s" @click="estadoFF(f, 'observado')">!</button>
                </template>
              </div>
              <div v-if="!ffs.length" class="text-[12px] text-mut py-1">Sin formulario firmado recibido.</div>
              <div v-if="ffs.length" class="text-[10.5px] text-mut mt-1">Cada archivo se sella con su huella criptográfica al recibirse.</div>
            </div>

            <div class="sm:col-span-2"><span class="text-mut">Formulario firmado:</span>
              <span v-if="det.candidato_firme" class="badge border-fp-600 bg-fp-600 text-white">★ Firmado</span>
              <span v-else class="badge border-amber-200 bg-amber-50 text-amber-800">Pendiente de firma</span>
              <span v-if="det.firme_fecha" class="text-mut"> · {{ fecha(det.firme_fecha) }}</span></div>
            <div v-if="det.notas" class="sm:col-span-2 whitespace-pre-line text-[12px] text-mut border-l-2 border-line pl-3">{{ det.notas }}</div>
          </div>

          <div v-else class="grid sm:grid-cols-2 gap-3">
            <div><label class="lbl">Teléfono</label><input v-model="dF.telefono" class="inp"></div>
            <div><label class="lbl">WhatsApp</label><input v-model="dF.whatsapp" class="inp"></div>
            <div><label class="lbl">Correo</label><input v-model="dF.email" class="inp"></div>
            <div><label class="lbl">Nivel académico</label><select v-model="dF.nivel_academico" class="inp"><option value="">—</option><option v-for="n in nivelOpts" :key="n" :value="n">{{ n }}</option></select></div>
            <div class="sm:col-span-2"><label class="lbl">Dirección</label><input v-model="dF.direccion" class="inp"></div>
            <div><label class="lbl">Ocupación</label><input v-model="dF.ocupacion" class="inp"></div>
            <div><label class="lbl">Vínculo con el partido</label><select v-model="dF.militancia" class="inp"><option value="">—</option><option>Militante</option><option>Miembro</option><option>Simpatizante</option></select></div>
            <div><label class="lbl">Cargo postulado</label><select v-model="dF.cargo_postulado" class="inp"><option v-for="(l, k) in cargoLbl" :key="k" :value="k">{{ l }}</option></select></div>
            <div class="sm:col-span-2"><label class="lbl">Detalle de experiencia</label><input v-model="dF.experiencia_detalle" class="inp"></div>
            <div class="sm:col-span-2 flex flex-wrap gap-4 pt-1">
              <label class="flex items-center gap-2 cursor-pointer"><input type="checkbox" v-model="dF.experiencia_2020" class="accent-fp-600 w-4 h-4"><span class="text-[13px]">Delegado(a) 2020</span></label>
              <label class="flex items-center gap-2 cursor-pointer"><input type="checkbox" v-model="dF.experiencia_2024" class="accent-fp-600 w-4 h-4"><span class="text-[13px]">Delegado(a) 2024</span></label>
              <label class="flex items-center gap-2 cursor-pointer"><input type="checkbox" v-model="dF.candidato_firme" class="accent-fp-600 w-4 h-4"><span class="text-[13px]"><b>Firmado</b> (firmado por los tres ejecutivos)</span></label>
            </div>
            <div class="sm:col-span-2"><label class="lbl">Notas</label><textarea v-model="dF.notas" class="inp min-h-[60px]"></textarea></div>
          </div>

          <!-- Gestión de etapa (Comisión) -->
          <div v-if="esAdmin && !detEdit" class="rounded-xl border border-fp-100 bg-fp-25 p-3.5">
            <div class="lbl !text-fp-800">Gestión de la Comisión</div>
            <div class="flex flex-wrap gap-2 mb-2.5">
              <button class="btn-s bg-fp-600 text-white rounded-xl hover:bg-fp-700" @click="setEstado('validado')" :disabled="detBusy">✓ Validar</button>
              <button class="btn-s bg-amber-500 text-white rounded-xl hover:bg-amber-600" @click="setEstado('devuelto')" :disabled="detBusy">↺ Devolver</button>
              <button class="btn-s bg-red-500 text-white rounded-xl hover:bg-red-600" @click="setEstado('rechazado')" :disabled="detBusy">✕ Rechazar</button>
            </div>
            <div class="flex flex-wrap gap-2 items-center">
              <select v-model="estadoSel" class="inp !w-auto !py-1.5 text-[12px]"><option value="" disabled>Otra etapa…</option><option v-for="(l, k) in estadoLbl" :key="k" :value="k">{{ l }}</option></select>
              <input v-model="estadoNota" class="inp !py-1.5 text-[12px] flex-1 min-w-[160px]" placeholder="Nota (obligatoria al devolver o rechazar)">
              <button class="btn-o btn-s" :disabled="!estadoSel || detBusy" @click="setEstado(estadoSel)">Aplicar</button>
            </div>
          </div>

          <div v-if="esAdmin && detBit.length" class="text-[11.5px] text-mut">
            <div class="lbl">Bitácora</div>
            <div v-for="b in detBit" :key="b.id" class="py-1 border-b border-line/60 last:border-0">{{ fechaHora(b.created_at) }} · <b>{{ b.accion }}</b><span v-if="b.detalle?.estado_nuevo"> → {{ estadoLbl[b.detalle.estado_nuevo] || b.detalle.estado_nuevo }}</span></div>
          </div>
        </div>

        <div class="p-4 border-t border-line flex flex-wrap justify-between gap-2 sticky bottom-0 bg-white rounded-b-2xl">
          <button v-if="docsCfg.permitir_individual" class="btn-o btn-s" @click="printIndividual(det)">⎙ Imprimir formulario</button>
          <div class="flex gap-2">
            <template v-if="canEditRow(det)">
              <button v-if="!detEdit" class="btn-o btn-s" @click="iniciarEdit">Editar</button>
              <template v-else>
                <button class="btn-o btn-s" @click="detEdit = false">Cancelar</button>
                <button class="btn-p btn-s" :disabled="detBusy" @click="guardarDet">{{ detBusy ? 'Guardando…' : 'Guardar cambios' }}</button>
              </template>
            </template>
            <button class="btn-o btn-s" @click="cerrarDet">Cerrar</button>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
