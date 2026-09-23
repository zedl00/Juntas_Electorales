<!-- src/views/RegistrarView.vue -->
<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { sb } from '../lib/supabase';
import { perfil, esAdmin, scopeAmplio, canRegister, verDistritos } from '../stores/auth';
import { catMap, catGrupos, nombreMun } from '../stores/catalogo';
import { cargarKpi, cargarTerr } from '../stores/kpi';
import { printIndividual, printBlanco } from '../stores/print';
import { rolLbl, cargoLbl, estadoLbl, reqLbl, reqDet, nivelOpts, expTitulo, expLbl, trasladoLbl } from '../lib/constantes';
import { fmt, fmtCed, soloDig, edad, cedulaValida, cedulaError } from '../lib/formato';
import { t } from '../stores/toasts';

defineOptions({ name: 'RegistrarView' });
const router = useRouter();

const regMun = ref(0), pasoR = ref(0), cedR = ref(''), buscR = ref(false);
const lkp = ref(null), lkpErr = ref(''), admOverride = ref(false);
const manual = ref(false);
const mf = reactive({ nombres: '', apellido1: '', apellido2: '', sexo: '', fnac: '' });
const fR = reactive({ telefono: '', whatsapp: '', email: '', direccion: '', nivel: '', ocupacion: '', militancia: '', cargo: '' });
const reqR = reactive({ militante: false, derechos: false, inscrito: false, no_candidatura: false, sin_incompat: false, disponibilidad: false, tecnologia: false });
const expDet = ref(''), notasR = ref(''), regBusy = ref(false), regOk = ref(null);
const exp20 = ref(false), exp24 = ref(false), expOtros = ref(false), firme = ref(false);

/* ── Evaluación del traslado: dónde vota frente a dónde trabajará ── */
const trasl = ref(null);

/* ── Colegio donde trabajará ── */
const colegios = ref([]), colBusy = ref(false), colElegido = ref(0);
const modoAsig = ref('si_difiere');

const cargarColegios = async () => {
  colegios.value = []; colBusy.value = true;
  const { data } = await sb.rpc('portal_colegios_territorio', {
    p_municipio: munReg.value, p_jce: perfil.value?.jce_id || null
  });
  colBusy.value = false;
  colegios.value = data || [];
};

/* Colegios agrupados por recinto, los que menos gente tienen primero */
const colPorRecinto = computed(() => {
  const g = {};
  colegios.value.forEach(c => { (g[c.recinto] = g[c.recinto] || []).push(c); });
  return Object.entries(g)
    .map(([recinto, items]) => ({ recinto, items, faltan: items.reduce((a, x) => a + x.faltan, 0) }))
    .sort((a, b) => b.faltan - a.faltan || a.recinto.localeCompare(b.recinto));
});

/* ¿Hay que pedir el colegio? */
const pideColegio = computed(() => {
  if (manual.value) return true;                       // sin padrón, no hay origen
  if (modoAsig.value === 'siempre') return true;
  if (modoAsig.value === 'automatico') return false;
  return mismatch.value;                               // si_difiere
});

/* El colegio que finalmente se guarda */
const colegioFinal = computed(() => {
  if (colElegido.value) return colElegido.value;
  if (!manual.value && !mismatch.value) return lkp.value?.id_colegio || null;
  return null;
});
const nombreMunReg = computed(() => catMap.value.get(munReg.value)?.nombre || '');

/* Texto del colegio que se guardará como lugar de trabajo (paso Confirmar) */
const colegioFinalTxt = computed(() => {
  if (!colegioFinal.value) return '';
  if (colElegido.value) {
    const c = colegios.value.find(x => x.id_colegio === colElegido.value);
    return c ? c.codigo + ' — ' + c.recinto : String(colElegido.value);
  }
  return lkp.value?.codigo_colegio || lkp.value?.id_colegio || '';
});
const evaluarTraslado = async () => {
  trasl.value = null;
  if (!lkp.value?.id_colegio || !munReg.value) return;
  const { data } = await sb.rpc('portal_evaluar_traslado', {
    p_colegio_padron: lkp.value.id_colegio,
    p_municipio_destino: munReg.value,
    p_jce_destino: perfil.value?.jce_id || null
  });
  if (data) trasl.value = data;
};

const munReg = computed(() => scopeAmplio.value ? (regMun.value || 0) : (perfil.value?.municipio_id || 0));
const selMunObj = computed(() => catMap.value.get(munReg.value) || null);
const esOclee = computed(() => selMunObj.value?.tipo === 'OCLEE');
const munRegistroNombre = computed(() => selMunObj.value?.nombre || perfil.value?.municipio || '—');
const mismatch = computed(() => !!(lkp.value?.encontrado && lkp.value.municipio_app_id && munReg.value && lkp.value.municipio_app_id !== munReg.value));
const telOk = computed(() => soloDig(fR.telefono).length === 10);
const waOk  = computed(() => soloDig(fR.whatsapp).length === 10);
const puedeP2 = computed(() => telOk.value && waOk.value && !!fR.cargo && !!fR.militancia);

const cedOk = computed(() => cedulaValida(cedR.value));
const cedMsg = computed(() => (soloDig(cedR.value).length >= 11 && !cedOk.value) ? cedulaError(cedR.value) : '');

const puedeP1 = computed(() => (cedOk.value && (manual.value
  ? !!(mf.nombres.trim() && mf.apellido1.trim() && mf.sexo)
  : !!(lkp.value?.encontrado && !lkp.value.ya_postulado && (!mismatch.value || esOclee.value || (esAdmin.value && admOverride.value))))) && (!pideColegio.value || !!colegioFinal.value));
const reqCant = computed(() => Object.values(reqR).filter(Boolean).length);
const reqTotal = computed(() => Object.keys(reqR).length);
const MIN_REQ = 4;
const reqsOk = computed(() => reqCant.value >= MIN_REQ);
const avisoReq = ref(false);
const verDetReq = ref(false);   /* las explicaciones vienen ocultas */

/* Con menos de la mitad de los requisitos se pide confirmación explícita */
const seguirPaso3 = () => {
  if (reqCant.value >= MIN_REQ) { avisoReq.value = false; pasoR.value = 3; return; }
  avisoReq.value = true;
};
const confirmarPocosReq = () => { avisoReq.value = false; pasoR.value = 3; };

const buscarCed = async () => {
  lkp.value = null; lkpErr.value = ''; admOverride.value = false; regOk.value = null; manual.value = false;
  exp20.value = false; exp24.value = false; expOtros.value = false; firme.value = false;
  if (scopeAmplio.value && !regMun.value) { t('Selecciona el territorio de registro', 'err'); return; }
  const d = soloDig(cedR.value);
  if (d.length < 8) { lkpErr.value = 'Escribe la cédula completa.'; return; }
  buscR.value = true;
  const { data, error } = await sb.rpc('portal_buscar_cedula', { p_ced: d });
  buscR.value = false;
  if (error) { lkpErr.value = 'Error consultando el padrón: ' + error.message; return; }
  if (!data?.encontrado) { lkpErr.value = 'La cédula no aparece en el padrón electoral activo.'; return; }
  lkp.value = data;
  exp24.value = !!data?.experiencia_2024;
  reqR.inscrito = !mismatch.value;
  await evaluarTraslado();
  if (pideColegio.value && !colegios.value.length) await cargarColegios();
};

onMounted(() => {
  sb.from('config_traslados').select('modo_asignacion').limit(1).maybeSingle()
    .then(({ data }) => { if (data?.modo_asignacion) modoAsig.value = data.modo_asignacion; });
});

const clearForm = () => {
  trasl.value = null; colElegido.value = 0;
  cedR.value = ''; lkp.value = null; lkpErr.value = ''; admOverride.value = false;
  Object.assign(fR, { telefono: '', whatsapp: '', email: '', direccion: '', nivel: '', ocupacion: '', militancia: '', cargo: '' });
  Object.keys(reqR).forEach(k => reqR[k] = false);
  expDet.value = ''; notasR.value = ''; pasoR.value = 0;
  exp20.value = false; exp24.value = false; expOtros.value = false; firme.value = false;
  manual.value = false; Object.assign(mf, { nombres: '', apellido1: '', apellido2: '', sexo: '', fnac: '' });
};
const resetReg = () => { regOk.value = null; clearForm(); };

const registrar = async () => {
  if (!cedulaValida(cedR.value)) { t('La cédula no es válida.', 'err'); return; }
  if ((manual.value ? false : !lkp.value?.encontrado) || !munReg.value) return;
  regBusy.value = true;
  let notas = notasR.value.trim();
  if (manual.value) {
    notas = '[Registro manual: no localizado en el padrón electoral · pendiente de verificación] ' + notas;
  } else if (mismatch.value && admOverride.value) {
    notas = '[Registro con advertencia de demarcación: según padrón vota en ' + (lkp.value.municipio_app || lkp.value.jce_municipio) + '] ' + notas;
  }
  const esM = manual.value;
  const payload = {
    cedula: esM ? soloDig(cedR.value) : lkp.value.cedula,
    nombres: esM ? mf.nombres.trim() : lkp.value.nombres,
    apellido1: esM ? mf.apellido1.trim() : lkp.value.apellido1,
    apellido2: esM ? (mf.apellido2.trim() || null) : (lkp.value.apellido2 || null),
    sexo: esM ? (mf.sexo || null) : (lkp.value.sexo || null),
    fecha_nacimiento: esM ? (mf.fnac || null) : (lkp.value.fecha_nacimiento || null),
    telefono: fR.telefono.trim(), whatsapp: fR.whatsapp.trim() || null, email: fR.email.trim() || null,
    direccion: fR.direccion.trim() || null, nivel_academico: fR.nivel || null, ocupacion: fR.ocupacion.trim() || null,
    militancia: fR.militancia || null,
    municipio_id: munReg.value,
    /* Dónde vota y dónde trabajará: siempre se guardan ambos */
    fuera_de_colegio: !esM && !!trasl.value && trasl.value.nivel !== 'mismo_colegio',
    municipio_padron_id: esM ? null : (trasl.value?.vota_municipio_id ?? lkp.value.municipio_app_id ?? null),
    jce_padron_id:       esM ? null : (trasl.value?.vota_jce_id ?? null),
    provincia_padron_id: esM ? null : (trasl.value?.vota_provincia_id ?? null),
    recinto_padron_desc: esM ? null : (trasl.value?.vota_recinto ?? lkp.value.recinto_desc ?? null),
    colegio_padron_desc: esM ? null : (trasl.value?.vota_colegio
      ?? [lkp.value.codigo_colegio || lkp.value.id_colegio, lkp.value.colegio_desc].filter(Boolean).join(' — ')),
    traslado_nivel:  esM ? null : (trasl.value?.nivel ?? null),
    traslado_estado: esM ? 'no_aplica' : (trasl.value?.estado ?? 'no_aplica'),
    autorizado_por: (!esM && trasl.value && trasl.value.nivel !== 'mismo_colegio')
      ? (perfil.value?.nombre || null) : null,
    id_colegio_padron: esM ? null : (lkp.value.id_colegio || null),
    colegio_asignado: colegioFinal.value,
    asignado_por: perfil.value?.nombre || null,
    asignado_en: new Date().toISOString(),
    codigo_colegio: esM ? null : (lkp.value.codigo_colegio || null),
    colegio_desc: esM ? null : (lkp.value.colegio_desc || null),
    codigo_recinto: esM ? null : (lkp.value.codigo_recinto || null),
    recinto_nombre: esM ? null : (lkp.value.recinto || null),
    circunscripcion: esM ? null : (lkp.value.circunscripcion || null),
    lugar_votacion: esM ? null : (lkp.value.lugar_votacion || null),
    cargo_postulado: fR.cargo,
    experiencia_2020: exp20.value,
    experiencia_otros: expOtros.value,
    experiencia_2024: exp24.value,
    candidato_firme: firme.value,
    experiencia_detalle: expDet.value.trim() || null, requisitos: { ...reqR }, notas: notas || null
  };
  const { data, error } = await sb.from('postulantes_2028').insert(payload).select().single();
  regBusy.value = false;
  if (error) {
    if (/postulantes_2028_cedula_key|duplicate/i.test(error.message)) t('Esta persona ya fue postulada.', 'err');
    else t('No se pudo registrar: ' + error.message, 'err');
    return;
  }
  regOk.value = data; clearForm();
  t('Postulación registrada · Nº ' + data.numero_formulario, 'ok');
  cargarKpi(); if (scopeAmplio.value) cargarTerr();
};

const imprimirBlanco = () => printBlanco(munReg.value || 0);
</script>

<template>
  <section class="max-w-2xl">
    <div class="flex items-start justify-between gap-3 mb-4">
      <div>
        <h2 class="font-serif text-xl font-bold">Registrar postulante</h2>
        <p class="text-[12.5px] text-mut mt-0.5">Preselección de delegados, suplentes y observadores de escrutinio.</p>
      </div>
      <button class="btn-o btn-s shrink-0" @click="imprimirBlanco">⎙ Formulario en blanco</button>
    </div>

    <div v-if="!canRegister" class="warn">Tu rol de <b>{{ rolLbl[perfil?.rol] }}</b> tiene acceso de consulta. El registro en la plataforma corresponde al <b>Encargado(a) Electoral</b> del territorio, conforme al Instructivo.</div>

    <template v-else>
      <!-- Territorio de registro -->
      <div class="card p-4 mb-4">
        <div class="lbl">Territorio de registro</div>
        <div v-if="!scopeAmplio" class="font-serif font-bold text-[15px]">
          {{ perfil?.distrito || perfil?.municipio }}
          <span class="font-sans text-[12px] font-normal text-mut">· {{ perfil?.distrito ? perfil?.municipio : perfil?.provincia }}</span>
          <span v-if="perfil?.distrito" class="badge border-line bg-paper text-mut ml-1 align-middle">Distrito</span>
        </div>
        <select v-else v-model.number="regMun" class="inp">
          <option :value="0" disabled>Selecciona el municipio / DM / OCLEE…</option>
          <optgroup v-for="g in catGrupos" :key="g.prov" :label="g.prov">
            <option v-for="m in g.items" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}{{ m.tipo === 'OCLEE' ? ' · OCLEE' : '' }}</option>
          </optgroup>
        </select>
        <div v-if="perfil?.distrito" class="text-[11px] text-mut mt-2">{{ fmt(perfil.colegios) }} colegios · meta {{ fmt(perfil.meta) }} postulantes <span class="text-mut/70">· solo este distrito</span></div>
        <div v-else-if="selMunObj" class="text-[11px] text-mut mt-2">{{ fmt(selMunObj.colegios) }} colegios · meta {{ fmt(selMunObj.meta) }} postulantes</div>
      </div>

      <!-- Pasos -->
      <div class="flex items-center gap-1.5 mb-4">
        <template v-for="(pTitle, i) in ['Cédula','Contacto','Requisitos','Confirmar']" :key="i">
          <div class="flex items-center gap-1.5">
            <span class="w-6 h-6 rounded-full grid place-items-center text-[11px] font-bold"
                  :class="pasoR > i ? 'bg-fp-600 text-white' : (pasoR === i ? 'bg-fp-100 text-fp-800 ring-2 ring-fp-300' : 'bg-white border border-line text-mut')">{{ i + 1 }}</span>
            <span class="text-[11px] font-semibold hidden sm:block" :class="pasoR >= i ? 'text-ink' : 'text-mut'">{{ pTitle }}</span>
          </div>
          <div v-if="i < 3" class="flex-1 h-px bg-line"></div>
        </template>
      </div>

      <!-- Paso 1: cédula -->
      <div v-show="pasoR === 0" class="card p-5 space-y-4">
        <div>
          <label class="lbl" for="rced">Cédula del postulante</label>
          <div class="flex gap-2">
            <input id="rced" v-model="cedR" class="inp text-lg tracking-wide" inputmode="numeric" placeholder="000-0000000-0" @keyup.enter="buscarCed">
            <button class="btn-p shrink-0" @click="buscarCed" :disabled="buscR || (scopeAmplio && !regMun)">{{ buscR ? 'Buscando…' : 'Buscar' }}</button>
          </div>
          <div v-if="scopeAmplio && !regMun" class="text-[11px] text-amber-700 mt-1.5">Primero selecciona el territorio de registro.</div>
        </div>

        <div v-if="cedMsg" class="errbx">{{ cedMsg }}</div>

        <div v-if="lkpErr && !manual" class="errbx">{{ lkpErr }}
          <button class="block mt-2 underline font-bold" @click="manual = true">✎ ¿No aparece? Registrar manualmente</button>
        </div>

        <div v-if="manual" class="rounded-xl border border-amber-200 bg-amber-50 p-4 space-y-3">
          <div class="flex items-center justify-between">
            <div class="text-[12.5px] font-bold text-amber-900">Registro manual · sin verificación de padrón</div>
            <button class="btn-o btn-s" @click="manual = false">Cancelar</button>
          </div>
          <p class="text-[11.5px] text-amber-900/85 leading-relaxed">Los datos electorales (colegio y recinto) quedan pendientes hasta que la Comisión verifique a la persona. El expediente queda marcado como registro manual en sus notas y en la bitácora.</p>
          <div class="grid sm:grid-cols-2 gap-3">
            <div><label class="lbl">Nombres *</label><input v-model="mf.nombres" class="inp !bg-white"></div>
            <div><label class="lbl">Primer apellido *</label><input v-model="mf.apellido1" class="inp !bg-white"></div>
            <div><label class="lbl">Segundo apellido</label><input v-model="mf.apellido2" class="inp !bg-white"></div>
            <div><label class="lbl">Sexo *</label><select v-model="mf.sexo" class="inp !bg-white"><option value="" disabled>Seleccionar…</option><option value="M">Masculino</option><option value="F">Femenino</option></select></div>
            <div><label class="lbl">Fecha de nacimiento</label><input v-model="mf.fnac" type="date" class="inp !bg-white"></div>
          </div>
        </div>

        <template v-if="lkp && lkp.encontrado">
          <div class="rounded-xl border border-fp-200 bg-fp-25 p-4">
            <div class="font-serif font-bold text-[17px]">{{ lkp.nombres }} {{ lkp.apellido1 }} {{ lkp.apellido2 || '' }}</div>
            <div class="text-[12px] text-mut mt-0.5">{{ fmtCed(lkp.cedula) }} · {{ lkp.sexo === 'M' ? 'Masculino' : 'Femenino' }} · {{ edad(lkp.fecha_nacimiento) }} años</div>
            <div class="mt-3 grid sm:grid-cols-2 gap-x-4 gap-y-1.5 text-[12.5px]">
              <div><span class="text-mut">Colegio:</span> <b>{{ lkp.codigo_colegio || lkp.id_colegio }}</b> — {{ lkp.colegio_desc }}</div>

            <!-- Dónde vota frente a dónde trabajará -->
            <div v-if="trasl && trasl.nivel && trasl.nivel !== 'mismo_colegio'"
                 class="mt-3 rounded-xl border p-3"
                 :class="trasl.estado === 'pendiente' ? 'border-amber-400 bg-amber-50' : 'border-fp-300 bg-fp-25'">
              <div class="text-[10.5px] font-bold uppercase tracking-[0.13em] mb-1.5"
                   :class="trasl.estado === 'pendiente' ? 'text-amber-800' : 'text-fp-700'">
                {{ trasl.estado === 'pendiente' ? 'Requiere autorización de la SNE' : 'Trabajará fuera de su colegio' }}
              </div>
              <div class="grid sm:grid-cols-2 gap-2.5 text-[12.5px]">
                <div class="rounded-lg bg-white/70 px-2.5 py-2">
                  <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Vota en</div>
                  <div class="font-semibold">{{ trasl.vota_recinto || '—' }}</div>
                  <div class="text-mut text-[11.5px]">{{ trasl.vota_colegio }}</div>
                </div>
                <div class="rounded-lg bg-white/70 px-2.5 py-2">
                  <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Trabajará en</div>
                  <div class="font-semibold">{{ perfil?.distrito || perfil?.municipio || nombreMunReg }}</div>
                  <div class="text-mut text-[11.5px]">{{ trasladoLbl[trasl.nivel] }}</div>
                </div>
              </div>
              <p class="text-[11.5px] mt-2 leading-snug"
                 :class="trasl.estado === 'pendiente' ? 'text-amber-900' : 'text-mut'">{{ trasl.msg }}</p>
            </div>
              <div><span class="text-mut">Recinto:</span> {{ lkp.recinto }}</div>
              <div class="sm:col-span-2"><span class="text-mut">Dirección:</span> {{ lkp.recinto_dir || '—' }}</div>
              <div><span class="text-mut">Municipio (JCE):</span> {{ lkp.jce_municipio }}</div>
              <div><span class="text-mut">Circunscripción:</span> {{ lkp.circunscripcion || '—' }}</div>
            </div>
            <div class="flex flex-wrap gap-2 mt-3">
              <span v-if="lkp.experiencia_2024" class="chip">✓ Delegado(a) 2024 ({{ lkp.experiencia_veces }})</span>
              <span v-if="lkp.lugar_votacion === 'E'" class="badge border-sky-200 bg-sky-50 text-sky-800">Vota en el exterior</span>
              <span v-if="lkp.es_usuario" class="badge border-line bg-white text-mut">Es usuario del portal</span>
            </div>
          </div>

          <div v-if="lkp.ya_postulado" class="errbx"><b>Ya está postulado(a).</b> Formulario {{ lkp.postulado_numero }} · {{ estadoLbl[lkp.postulado_estado] }} · {{ nombreMun(lkp.postulado_municipio_id) }}. El Instructivo permite una sola postulación por persona.</div>

          <template v-else>
            <div v-if="mismatch && !esOclee" class="space-y-2">
              <div v-if="!esAdmin" class="errbx"><b>No pertenece a esta demarcación.</b> Según el padrón vota en <b>{{ lkp.municipio_app || lkp.jce_municipio }}</b>. El Instructivo requiere estar inscrito(a) en el Registro Electoral de la demarcación donde ejercerá sus funciones.</div>
              <div v-else class="warn">
                <b>Advertencia:</b> según el padrón vota en <b>{{ lkp.municipio_app || lkp.jce_municipio }}</b>, no en el territorio seleccionado.
                <label class="flex items-center gap-2 mt-2 cursor-pointer font-semibold"><input type="checkbox" v-model="admOverride" class="accent-fp-600"> Registrar de todos modos (queda constancia en el expediente)</label>

                <!-- Colegio donde trabajará: solo cuando la persona viene de fuera -->
                <div v-if="admOverride && pideColegio" class="mt-2.5 pt-2.5 border-t border-amber-200">
                  <label class="lbl !mb-1">Colegio donde trabajará *</label>
                  <select v-model.number="colElegido" class="inp !bg-white !py-2 text-[13px]" :disabled="colBusy">
                    <option :value="0">{{ colBusy ? 'Cargando colegios…' : 'Elegir colegio…' }}</option>
                    <optgroup v-for="g in colPorRecinto" :key="g.recinto" :label="g.recinto">
                      <option v-for="c in g.items" :key="c.id_colegio" :value="c.id_colegio">
                        {{ c.codigo }} — {{ c.personas }} de 3{{ c.faltan ? ' · faltan ' + c.faltan : ' · completo' }}
                      </option>
                    </optgroup>
                  </select>
                  <p class="text-[11px] text-amber-800 mt-1 leading-snug">
                    Los recintos con más faltantes aparecen primero. Esta persona contará para el colegio
                    que elijas, no para el suyo del padrón.
                  </p>
                </div>
              </div>
            </div>
            <div v-if="esOclee" class="okbx">Territorio del exterior: se registrará bajo la <b>{{ selMunObj?.nombre }}</b>. La verificación de demarcación no aplica.</div>
          </template>
        </template>

        <div class="flex justify-end">
          <button class="btn-p" :disabled="!puedeP1" @click="pasoR = 1">Continuar →</button>
        </div>
      </div>

      <!-- Paso 2: contacto y perfil -->
      <div v-show="pasoR === 1" class="card p-5">
        <p class="text-[12px] text-mut mb-3">Los campos marcados con <span class="text-red-600 font-bold">*</span> son obligatorios para continuar.</p>
        <div class="grid sm:grid-cols-2 gap-4">
          <div><label class="lbl lbl-req">Teléfono</label><input v-model="fR.telefono" class="inp" :class="!telOk && fR.telefono ? '!border-red-300' : ''" inputmode="tel" placeholder="809-000-0000">
            <div v-if="fR.telefono && !telOk" class="text-[11px] text-red-600 mt-1">Debe tener 10 dígitos, por ejemplo 809 555 1234.</div></div>
          <div><label class="lbl lbl-req">WhatsApp</label><div class="flex gap-2"><input v-model="fR.whatsapp" class="inp" inputmode="tel" placeholder="809-000-0000"><button type="button" class="btn-o btn-s shrink-0" @click="fR.whatsapp = fR.telefono">Igual</button></div></div>
          <div><label class="lbl">Correo electrónico</label><input v-model="fR.email" class="inp" type="email" placeholder="opcional"></div>
          <div><label class="lbl">Nivel académico</label><select v-model="fR.nivel" class="inp"><option value="">Seleccionar…</option><option v-for="n in nivelOpts" :key="n" :value="n">{{ n }}</option></select></div>
          <div class="sm:col-span-2"><label class="lbl">Dirección</label><input v-model="fR.direccion" class="inp" placeholder="Calle, sector, referencia"></div>
          <div><label class="lbl">Ocupación</label><input v-model="fR.ocupacion" class="inp" placeholder="Ej. Docente"></div>
          <div><label class="lbl lbl-req">Vínculo con el partido</label><select v-model="fR.militancia" class="inp"><option value="">Seleccionar…</option><option>Militante</option><option>Miembro</option><option>Dirigente</option></select></div>
          <div><label class="lbl lbl-req">Cargo al que se postula</label><select v-model="fR.cargo" class="inp"><option value="" disabled>Seleccionar…</option><option v-for="(l, k) in cargoLbl" :key="k" :value="k">{{ l }}</option></select></div>
        </div>
        <div class="flex justify-between mt-5">
          <button class="btn-o" @click="pasoR = 0">← Atrás</button>
          <button class="btn-p" :disabled="!puedeP2" @click="pasoR = 2">Continuar →</button>
        </div>
      </div>

      <!-- Paso 3: requisitos -->
      <div v-show="pasoR === 2" class="card p-5">
        <div class="flex flex-wrap items-baseline gap-2 mb-3">
          <p class="text-[12.5px] text-mut mr-auto">Requisitos mínimos del Instructivo (Sección III). El Encargado(a) Electoral certifica cada punto:</p>
          <button class="text-[11.5px] text-fp-700 font-semibold hover:underline shrink-0"
                  @click="verDetReq = !verDetReq">
            {{ verDetReq ? 'Ocultar' : 'ⓘ Ver' }} qué verificar
          </button>
        </div>
        <label v-for="(rq, k) in reqLbl" :key="k" class="flex items-start gap-2.5 py-2 border-b border-line/60 last:border-0 cursor-pointer">
          <input type="checkbox" v-model="reqR[k]" class="accent-fp-600 mt-0.5 w-4 h-4" :disabled="!manual && k === 'inscrito' && !mismatch">
          <span class="text-[13px] leading-snug">
            {{ rq }}<span v-if="!manual && k === 'inscrito' && !mismatch" class="text-fp-700 font-semibold"> · verificado en padrón ✓</span>
            <span v-if="verDetReq" class="block text-[11.5px] text-mut mt-1 leading-snug">{{ reqDet[k] }}</span>
          </span>
        </label>
        <div class="mt-4 rounded-xl bg-paper border border-line p-3.5">
          <div class="flex items-center justify-between mb-2">
            <span class="text-[12.5px] font-semibold">Ha servido en procesos electorales anteriores</span>
            <span v-if="lkp?.experiencia_2024" class="chip">✓ Detectada en 2024</span>
            <span class="text-[11px] text-mut w-full">Cualquier función servida: titular, suplente u observador.</span>
          </div>
          <div class="flex flex-wrap gap-4">
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="exp20" class="accent-fp-600 w-4 h-4">
              <span class="text-[13px]">Proceso <b>2020</b></span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="exp24" class="accent-fp-600 w-4 h-4">
              <span class="text-[13px]">Proceso <b>2024</b></span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="expOtros" class="accent-fp-600 w-4 h-4">
              <span class="text-[13px]"><b>Otros procesos</b></span>
            </label>
          </div>
          <textarea v-model="expDet" class="inp mt-2.5 min-h-[56px]" placeholder="Detalle (opcional): procesos, funciones, recinto…"></textarea>
        </div>

        <label class="mt-3 rounded-xl border p-3.5 flex items-start gap-2.5 cursor-pointer transition-colors"
               :class="firme ? 'border-fp-600 bg-fp-25' : 'border-line bg-paper'">
          <input type="checkbox" v-model="firme" class="accent-fp-600 mt-0.5 w-4 h-4">
          <span class="text-[13px] leading-snug">
            <b>Firmado</b>
            <span class="block text-[11.5px] text-mut mt-0.5">El formulario fue firmado por Presidente(a), Secretario(a) General y Encargado(a) Electoral antes de la preselección.</span>
          </span>
        </label>
        <div class="mt-3 flex items-center gap-2 text-[12px]">
          <span class="badge" :class="reqCant >= 6 ? 'border-fp-600 bg-fp-600 text-white'
            : (reqCant >= MIN_REQ ? 'border-amber-300 bg-amber-50 text-amber-800' : 'border-red-200 bg-red-50 text-red-700')">
            {{ reqCant }} de {{ reqTotal }}
          </span>
          <span class="text-mut">requisitos certificados</span>
        </div>

        <div v-if="avisoReq" class="mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3.5">
          <p class="text-[13px] font-semibold text-amber-900 mb-1">Este postulante cumple pocos requisitos</p>
          <p class="text-[12px] text-amber-800 leading-snug mb-3">
            Certificaste {{ reqCant }} de {{ reqTotal }}. El sistema no lo impide, pero conviene valorar si hay
            alguien más idóneo en la demarcación. El registro quedará marcado para revisión de la Comisión.
          </p>
          <div class="flex flex-wrap gap-2">
            <button class="btn-p btn-s" @click="confirmarPocosReq">Continuar de todos modos</button>
            <button class="btn-o btn-s" @click="avisoReq = false">Volver a revisar</button>
          </div>
        </div>
        <div class="flex justify-between mt-5">
          <button class="btn-o" @click="pasoR = 1">← Atrás</button>
          <button class="btn-p" @click="seguirPaso3">Continuar →</button>
        </div>
      </div>

      <!-- Paso 4: confirmar -->
      <div v-show="pasoR === 3" class="card p-5">
        <div class="rounded-xl border border-line bg-paper p-4 space-y-1.5 text-[13px]">
          <div v-if="manual" class="badge border-amber-200 bg-amber-50 text-amber-800 mb-1">Registro manual · pendiente de verificación</div>
          <div class="font-serif font-bold text-[16px]">{{ manual ? (mf.nombres + ' ' + mf.apellido1 + ' ' + (mf.apellido2 || '')) : (lkp?.nombres + ' ' + lkp?.apellido1 + ' ' + (lkp?.apellido2 || '')) }}</div>
          <div><span class="text-mut">Cédula:</span> {{ fmtCed(manual ? cedR : lkp?.cedula) }} · <span class="text-mut">Cargo:</span> <b>{{ cargoLbl[fR.cargo] }}</b></div>
          <div><span class="text-mut">Municipio:</span> {{ munRegistroNombre }} · <span class="text-mut">Colegio donde trabajará:</span> {{ manual ? 'Pendiente de verificación' : (colegioFinalTxt || 'Sin asignar') }}</div>
          <div v-if="!manual && mismatch" class="text-[12px]"><span class="text-mut">Vota en (padrón):</span> {{ lkp?.codigo_colegio || lkp?.id_colegio }} · {{ lkp?.municipio_app || lkp?.jce_municipio }}</div>
          <div><span class="text-mut">Teléfono:</span> {{ fR.telefono }}<span v-if="fR.whatsapp"> · WhatsApp {{ fR.whatsapp }}</span></div>
          <div v-if="exp20 || exp24" class="text-fp-700 font-semibold">✓ Experiencia como delegado(a): {{ [exp20 ? '2020' : null, exp24 ? '2024' : null].filter(Boolean).join(' y ') }}</div>
          <div v-if="firme"><span class="badge border-fp-600 bg-fp-600 text-white">★ Firmado</span> <span class="text-[11.5px] text-mut">firmado por los tres ejecutivos</span></div>
        </div>
        <div class="mt-4"><label class="lbl">Notas internas (opcional)</label><textarea v-model="notasR" class="inp min-h-[60px]" placeholder="Observaciones para la Comisión…"></textarea></div>
        <div class="flex justify-between mt-5">
          <button class="btn-o" @click="pasoR = 2">← Atrás</button>
          <button class="btn-p" :disabled="regBusy" @click="registrar">{{ regBusy ? 'Guardando…' : 'Registrar postulante' }}</button>
        </div>
      </div>

      <!-- Éxito -->
      <div v-if="regOk" class="card p-6 mt-4 text-center">
        <div class="text-[11px] font-semibold uppercase tracking-wider text-fp-700">Postulación registrada</div>
        <div class="font-serif text-3xl font-bold mt-2 inline-block border-2 border-dashed border-fp-300 rounded-xl px-5 py-2 bg-fp-25">Nº {{ regOk.numero_formulario }}</div>
        <div class="mt-2 text-sm">{{ regOk.nombres }} {{ regOk.apellido1 }} · {{ cargoLbl[regOk.cargo_postulado] }}</div>
        <div class="flex flex-wrap justify-center gap-2 mt-5">
          <button class="btn-p" @click="printIndividual(regOk)">⎙ Imprimir formulario para firmas</button>
          <button class="btn-o" @click="resetReg">Registrar otro</button>
          <button class="btn-o" @click="router.push('/postulantes')">Ver listado</button>
        </div>
      </div>
    </template>
  </section>
</template>
