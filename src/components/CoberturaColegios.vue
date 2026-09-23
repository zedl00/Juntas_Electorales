<!-- src/components/CoberturaColegios.vue -->
<script setup>
import { perfil, verDistritos } from '../stores/auth';
import { ref, computed, watch } from 'vue';
import { sb } from '../lib/supabase';
import { printCobertura, printResumen, printBusy , sellarImpresion } from '../stores/print';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';

const props = defineProps({
  municipioId: { type: Number, required: true },
  jceId:  { type: Number, default: 0 },
  circId: { type: Number, default: 0 },
  titulo: { type: String, default: '' }
});

const filas = ref([]);
const busy = ref(false);
const soloInc = ref(false);
const errMsg = ref('');

const cargar = async () => {
  if (!props.municipioId) { filas.value = []; return; }
  busy.value = true; errMsg.value = '';
  const { data, error } = await sb.rpc('portal_cobertura_colegios', {
    p_municipio: props.municipioId,
    p_jce:  props.jceId  || null,
    p_circ: props.circId || null
  });
  busy.value = false;
  if (error) { errMsg.value = error.message; t('No se pudo cargar la cobertura: ' + error.message, 'err'); return; }
  filas.value = data || [];
};
watch(() => [props.municipioId, props.jceId, props.circId], cargar, { immediate: true });

const completos = computed(() => filas.value.filter(f => f.personas >= 3).length);
const parciales = computed(() => filas.value.filter(f => f.personas > 0 && f.personas < 3).length);
const vacios    = computed(() => filas.value.filter(f => !f.personas).length);
const visibles  = computed(() => soloInc.value ? filas.value.filter(f => f.personas < 3) : filas.value);
const imprimir = async (nombre, fn) => {
  const r = await sellarImpresion(nombre, props.titulo || '', filas.value.length);
  if (!r.ok) { t(r.msg || 'Tu acceso no tiene autorización para imprimir.', 'err'); return; }
  fn(props.municipioId, props.jceId, props.circId);
};

const multiDist = computed(() => verDistritos.value && new Set(filas.value.map(f => f.jce_id)).size > 1);
/* La circunscripción solo se muestra donde el territorio está realmente dividido */
const multiCirc = computed(() => new Set(filas.value.map(f => f.circunscripcion).filter(Boolean)).size > 1);
const nCols = computed(() => multiCirc.value ? 9 : 8);

/* Agrupar Distrito → Recinto conservando el orden de la consulta */
const grupos = computed(() => {
  const g = []; let d = null, r = null;
  visibles.value.forEach(f => {
    if (!d || d.jce_id !== f.jce_id) { d = { jce_id: f.jce_id, distrito: f.distrito, recintos: [], n: 0, ok: 0 }; g.push(d); r = null; }
    if (!r || r.recinto !== f.recinto) { r = { recinto: f.recinto, dir: f.recinto_dir, filas: [] }; d.recintos.push(r); }
    r.filas.push(f); d.n++; if (f.personas >= 3) d.ok++;
  });
  return g;
});

const badgeDe = f => f.personas >= 3
  ? { cls: 'border-fp-600 bg-fp-600 text-white', txt: 'Completo' }
  : (f.personas > 0
      ? { cls: 'border-amber-200 bg-amber-50 text-amber-800', txt: 'Faltan ' + (3 - f.personas) }
      : { cls: 'border-red-200 bg-red-50 text-red-700', txt: 'Sin registro' });
</script>

<template>
  <div class="card overflow-hidden">
    <div class="p-4 border-b border-line flex flex-wrap items-center gap-2">
      <h3 class="font-serif font-bold text-[15px] mr-auto">{{ titulo || 'Cobertura por colegio electoral' }}</h3>
      <span class="chip">✓ Completos: {{ fmt(completos) }}</span>
      <span class="badge border-amber-200 bg-amber-50 text-amber-800">Incompletos: {{ fmt(parciales) }}</span>
      <span class="badge border-red-200 bg-red-50 text-red-700">Sin registro: {{ fmt(vacios) }}</span>
      <label class="flex items-center gap-1.5 text-[11px] font-semibold text-mut cursor-pointer ml-1">
        <input type="checkbox" v-model="soloInc" class="accent-fp-600"> Solo incompletos
      </label>
      <button v-if="perfil?.puede_imprimir !== false" class="btn-o btn-s" @click="imprimir('Formulario general del municipio', printResumen)" :disabled="printBusy || busy">⎙ Formulario general del municipio</button>
      <button v-if="perfil?.puede_imprimir !== false" class="btn-o btn-s" @click="imprimir('Reporte para validación', printCobertura)" :disabled="printBusy || busy">⎙ Reporte para validación</button>
    </div>

    <div v-if="errMsg" class="errbx m-4">No se pudo cargar la cobertura: {{ errMsg }}
      <button class="underline font-bold ml-2" @click="cargar">Reintentar</button>
      <span class="block mt-1 text-[11px]">Si menciona «does not exist», «structure of query» o «Could not find the function», ejecuta en Supabase la última fase SQL entregada.</span>
    </div>

    <!-- Móvil: tarjetas por colegio -->
    <div class="sm:hidden">
      <template v-for="d in grupos" :key="'m' + d.jce_id">
        <div v-if="multiDist" class="px-4 py-2 bg-fp-600 text-white text-[11.5px] font-bold uppercase tracking-wide">
          {{ d.distrito }} <span class="font-normal normal-case opacity-80">· {{ d.ok }} de {{ d.n }}</span>
        </div>
        <template v-for="g in d.recintos" :key="'m' + d.jce_id + g.recinto">
          <div class="px-4 py-1.5 bg-fp-25/70 text-[11.5px] font-bold text-fp-800 border-b border-fp-100">{{ g.recinto }}</div>
          <div v-for="f in g.filas" :key="'m' + f.id_colegio" class="px-4 py-3 border-b border-line/60">
            <div class="flex items-center justify-between gap-2 mb-1.5">
              <span class="font-semibold text-[13.5px]">{{ f.colegio }}</span>
              <span class="badge shrink-0" :class="badgeDe(f).cls">{{ badgeDe(f).txt }}</span>
            </div>
            <div class="flex items-center gap-3 text-[12px] text-mut">
              <span class="tabular-nums font-semibold text-ink">{{ f.personas }}<span class="font-normal text-mut"> / 3</span></span>
              <span v-if="f.titulares" title="Titular">T{{ f.titulares }}</span>
              <span v-if="f.suplentes" title="Suplente">S{{ f.suplentes }}</span>
              <span v-if="f.observadores" title="Observador">O{{ f.observadores }}</span>
              <span v-if="f.indistintos">I{{ f.indistintos }}</span>
              <span class="ml-auto tabular-nums">{{ fmt(f.inscritos) }} electores</span>
            </div>
          </div>
        </template>
      </template>
      <div v-if="!visibles.length && !busy && !errMsg" class="px-4 py-8 text-center text-mut text-[13px]">
        {{ soloInc ? 'No hay colegios incompletos: cobertura al 100%.' : 'Este territorio aún no tiene colegios en la carga de datos de la JCE. Se completará con la próxima actualización.' }}
      </div>
      <div v-if="busy" class="px-4 py-8 text-center text-mut text-[13px]">Cargando cobertura…</div>
    </div>

    <!-- Escritorio: tabla completa -->
    <div class="hidden sm:block overflow-x-auto">
      <table class="w-full min-w-[760px]">
        <thead class="bg-paper border-b border-line">
          <tr>
            <th class="th">Colegio</th>
            <th v-if="multiCirc" class="th">Circunscripción</th>
            <th class="th text-right">Inscritos</th>
            <th class="th text-center">Titular</th>
            <th class="th text-center">Suplente</th>
            <th class="th text-center">Observador</th>
            <th class="th text-center">Indist.</th>
            <th class="th text-center">Total / 3</th>
            <th class="th">Estado</th>
          </tr>
        </thead>
        <template v-for="d in grupos" :key="d.jce_id">
          <tbody>
            <tr v-if="multiDist" class="bg-fp-600 text-white">
              <td :colspan="nCols" class="px-3 py-1.5 text-[11.5px] font-bold uppercase tracking-wide">
                {{ d.distrito }} <span class="font-normal normal-case opacity-80">· {{ d.n }} colegios · {{ d.ok }} completos</span>
              </td>
            </tr>
            <template v-for="g in d.recintos" :key="d.jce_id + g.recinto">
              <tr class="bg-fp-25/70 border-b border-fp-100">
                <td :colspan="nCols" class="px-3 py-1.5 text-[11.5px] font-bold text-fp-800">
                  {{ g.recinto }} <span class="font-normal text-mut">· {{ g.filas.length }} colegios<span v-if="g.dir"> · {{ g.dir }}</span></span>
                </td>
              </tr>
              <tr v-for="f in g.filas" :key="f.id_colegio" class="border-b border-line/60">
                <td class="td font-semibold whitespace-nowrap">{{ f.colegio }}</td>
                <td v-if="multiCirc" class="td text-[12px] text-mut whitespace-nowrap">{{ f.circunscripcion }}</td>
                <td class="td text-right tabular-nums text-mut">{{ fmt(f.inscritos) }}</td>
                <td class="td text-center tabular-nums" :class="f.titulares ? 'font-bold text-fp-700' : 'text-mut/50'">{{ f.titulares }}</td>
                <td class="td text-center tabular-nums" :class="f.suplentes ? 'font-bold text-fp-700' : 'text-mut/50'">{{ f.suplentes }}</td>
                <td class="td text-center tabular-nums" :class="f.observadores ? 'font-bold text-fp-700' : 'text-mut/50'">{{ f.observadores }}</td>
                <td class="td text-center tabular-nums" :class="f.indistintos ? 'font-semibold' : 'text-mut/50'">{{ f.indistintos }}</td>
                <td class="td text-center tabular-nums font-bold">{{ f.personas }}<span class="text-mut font-normal"> / 3</span></td>
                <td class="td"><span class="badge" :class="badgeDe(f).cls">{{ badgeDe(f).txt }}</span></td>
              </tr>
            </template>
          </tbody>
        </template>
        <tbody>
          <tr v-if="!visibles.length && !busy && !errMsg"><td :colspan="nCols" class="td text-center text-mut py-8">{{ soloInc ? 'No hay colegios incompletos: cobertura al 100%.' : 'Este territorio aún no tiene colegios en la carga de datos de la JCE. Se completará con la próxima actualización.' }}</td></tr>
          <tr v-if="busy"><td :colspan="nCols" class="td text-center text-mut py-8">Cargando cobertura…</td></tr>
        </tbody>
      </table>
    </div>
    <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
      {{ fmt(filas.length) }} colegios en el filtro actual · un colegio está completo con 3 personas en proceso (rechazados y no aprobados no cuentan).
    </div>
  </div>
</template>
