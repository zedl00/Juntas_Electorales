<!-- src/views/InicioView.vue -->
<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { sb } from '../lib/supabase';
import { perfil, scopeAmplio, esAdmin, esNacional, verDistritos } from '../stores/auth';
import { regiones, provsOf, catMap, munPadres } from '../stores/catalogo';
import {
  kpi, kpiBusy, avancePct, semColor, estadoBars, cargoBars, refrescar,
  terrBusy, terrFRegion, terrFProv, terrFQ, terrSinAct, terrOrden, tArrow, terrView, cob
} from '../stores/kpi';
import { estadoLbl, cargoLbl } from '../lib/constantes';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';
import CoberturaColegios from '../components/CoberturaColegios.vue';
import AnilloAvance from '../components/AnilloAvance.vue';
import TableroEjecutivo from '../components/TableroEjecutivo.vue';

defineOptions({ name: 'InicioView' });
const router = useRouter();
const irTerritorio = tr => router.push({ path: '/postulantes', query: { mun: tr.municipio_id } });

/* ── Cadena de filtros: Ámbito → Región → Provincia → Municipio → Distrito → Circunscripción ── */
const terrAmbito = ref('');
const munF = ref(0);
const distF = ref(0);
const circF = ref(0);

const esExterior = computed(() => terrAmbito.value === 'oclee' || terrFRegion.value === 'Exterior');
const regionesF = computed(() => terrAmbito.value === 'oclee' ? regiones.value.filter(r => r === 'Exterior')
  : (terrAmbito.value === 'nacional' ? regiones.value.filter(r => r !== 'Exterior') : regiones.value));
const setAmbito = () => {
  terrFProv.value = ''; munF.value = 0;
  terrFRegion.value = terrAmbito.value === 'oclee' ? 'Exterior' : '';
};
const setRegion = () => { terrFProv.value = ''; munF.value = 0; };
const setProv   = () => { munF.value = 0; };

/* Municipio efectivo: el elegido (alcance amplio) o el propio (roles municipales) */
const munEfectivo = computed(() => scopeAmplio.value ? munF.value : (perfil.value?.municipio_id || 0));
const munObj = computed(() => catMap.value.get(munEfectivo.value) || null);
const esOclee = computed(() => (munObj.value?.tipo || perfil.value?.tipo_territorio) === 'OCLEE');

/* Distritos y circunscripciones del municipio efectivo */
const dists = ref([]);
const circs = ref([]);
const distBusy = ref(false);

const cargarNiveles = async id => {
  distF.value = 0; circF.value = 0; dists.value = []; circs.value = [];
  if (!id) return;
  distBusy.value = true;
  const [d, c] = await Promise.all([
    sb.rpc('portal_kpi_distritos', { p_municipio: id }),
    sb.from('portal_circunscripciones').select('circ_id,nombre,colegios,meta').eq('municipio_id', id).order('nombre')
  ]);
  distBusy.value = false;
  if (d.error) { t('Distritos: ' + d.error.message, 'err'); }
  else { dists.value = verDistritos.value ? (d.data || []) : []; }
  if (!c.error) circs.value = c.data || [];
};
watch(munEfectivo, cargarNiveles, { immediate: true });

const distSelObj = computed(() => dists.value.find(d => d.jce_id === distF.value) || null);

const terrViewF = computed(() => terrView.value.filter(r => {
  if (terrAmbito.value === 'oclee'    && r.tipo !== 'OCLEE') return false;
  if (terrAmbito.value === 'nacional' && r.tipo === 'OCLEE') return false;
  if (munF.value) return r.municipio_id === munF.value;
  return true;
}));
const sinActF = computed(() => terrViewF.value.filter(r => !r.total).length);

const kf = ref(null), kfBusy = ref(false);
const cargarKf = async () => {
  kfBusy.value = true;
  const { data, error } = await sb.rpc('portal_kpi_filtro', {
    p_ambito:    terrAmbito.value || null,
    p_region:    terrFRegion.value || null,
    p_provincia: terrFProv.value || null,
    p_municipio: (scopeAmplio.value ? munF.value : perfil.value?.municipio_id) || null,
    p_jce:       distF.value || null,
    p_circ:      circF.value || null
  });
  kfBusy.value = false;
  if (!error) kf.value = data;
};
watch([terrAmbito, terrFRegion, terrFProv, munF, distF, circF], cargarKf, { immediate: true });

const pctKf = computed(() => (kf.value?.meta ? Math.round(kf.value.registrados * 100 / kf.value.meta) : 0));
const nivelTxt = computed(() => {
  if (circF.value) return circs.value.find(c => c.circ_id === circF.value)?.nombre || 'Circunscripción';
  if (distF.value) return dists.value.find(d => d.jce_id === distF.value)?.distrito || 'Distrito';
  if (munF.value)  return catMap.value.get(munF.value)?.nombre || 'Municipio';
  if (terrFProv.value) return provsOf(terrFRegion.value).find(p => p.id === terrFProv.value)?.nombre || 'Provincia';
  if (terrFRegion.value) return 'Región ' + terrFRegion.value;
  if (terrAmbito.value === 'oclee') return 'Exterior · todas las OCLEE';
  if (terrAmbito.value === 'nacional') return 'Territorio nacional';
  return 'Nacional + Exterior';
});

const cobFiltro = computed(() => {
  const a = { colegios: 0, completos: 0, parciales: 0, vacios: 0 };
  terrViewF.value.forEach(r => {
    const c = cob.value.get(r.municipio_id);
    if (c) { a.colegios += +c.colegios; a.completos += +c.completos; a.parciales += +c.parciales; a.vacios += +c.vacios; }
  });
  return a;
});
const cobDe = id => cob.value.get(id) || null;
const pendientesJCE = computed(() => terrViewF.value.filter(r => !r.meta).length);

/* Avance por región, agregado del filtro activo */
const porRegion = computed(() => {
  const m = new Map();
  terrViewF.value.forEach(r => {
    const k = r.macroregion || 'Sin región';
    const a = m.get(k) || { region: k, meta: 0, total: 0 };
    a.meta += Number(r.meta || 0); a.total += Number(r.total || 0);
    m.set(k, a);
  });
  return [...m.values()]
    .map(a => ({ ...a, pct: a.meta ? Math.round(a.total * 100 / a.meta) : 0 }))
    .sort((x, y) => y.meta - x.meta);
});

/* Estado de la cadena de integridad */
const sello = ref(null);
const verSello = async () => {
  if (!esNacional.value) return;
  const { data, error } = await sb.rpc('portal_verificar_cadena');
  if (!error && data?.length) sello.value = data[0];
};
onMounted(verSello);
const pctD = d => (+d.meta ? Math.round(+d.total * 100 / +d.meta) : 0);
const tituloCob = computed(() => {
  const m = catMap.value.get(munEfectivo.value)?.nombre || perfil.value?.municipio || '';
  const d = distSelObj.value ? ' · ' + distSelObj.value.distrito : '';
  return 'Cobertura por colegio · ' + m + d;
});
</script>

<template>
  <section class="space-y-5">
    <div class="flex items-center justify-between">
      <h2 class="font-serif text-xl font-bold">Seguimiento</h2>
      <button class="btn-o btn-s" @click="refrescar" :disabled="kpiBusy">{{ kpiBusy ? 'Actualizando…' : 'Actualizar' }}</button>
    </div>

    <!-- Panel principal: anillo y registrados -->
    <div class="rounded-2xl bg-fp-700 text-white px-5 py-6 sm:px-7">
      <div class="flex items-center gap-5 sm:gap-7">
        <AnilloAvance :pct="avancePct" :size="104" :grosor="12" claro />
        <div class="min-w-0">
          <div class="text-[10.5px] font-bold uppercase tracking-[0.16em] text-fp-100/85">Registrados</div>
          <div class="text-[34px] sm:text-[40px] font-bold leading-none tabular-nums mt-1">{{ fmt(kpi?.total ?? 0) }}</div>
          <div class="text-[12.5px] text-fp-100/85 mt-1.5">de {{ fmt(kpi?.meta ?? 0) }} · meta 3 × colegio</div>
        </div>
      </div>
    </div>

    <!-- Indicadores -->
    <div class="grid grid-cols-2 gap-3">
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Colegios cubiertos</div>
        <div class="text-[21px] font-bold tabular-nums leading-tight mt-0.5">{{ fmt(kpi?.colegios_cubiertos ?? 0) }}</div>
        <div class="text-[11px] text-mut">de {{ fmt(kpi?.colegios ?? 0) }}</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Experiencia previa</div>
        <div class="text-[21px] font-bold tabular-nums leading-tight mt-0.5">{{ fmt(kpi?.con_experiencia ?? 0) }}</div>
        <div class="text-[11px] text-mut">delegados(as) antes</div>
      </div>
    </div>

    <div class="flex flex-wrap gap-2">
      <span class="chip">Hoy: {{ fmt(kpi?.hoy ?? 0) }}</span>
      <span class="chip">Últimos 7 días: {{ fmt(kpi?.semana ?? 0) }}</span>
    </div>

    <!-- Integridad -->

    <TableroEjecutivo v-if="scopeAmplio" :kpi="kpi || {}" :totales="kf || {}" :por-region="porRegion" />

    <div v-if="sello" class="flex items-start gap-2.5 rounded-xl px-4 py-3"
         :class="+sello.alterados > 0 ? 'bg-red-50 border border-red-200' : 'bg-fp-25 border border-fp-100'">
      <span class="text-[15px] leading-none mt-0.5" :class="+sello.alterados > 0 ? 'text-red-600' : 'text-fp-700'">
        {{ +sello.alterados > 0 ? '⚠' : (+sello.total === 0 ? '◈' : '✓') }}
      </span>
      <span class="text-[12px] leading-snug" :class="+sello.alterados > 0 ? 'text-red-700' : 'text-fp-800'">
        <template v-if="+sello.alterados > 0"><b>Atención:</b> {{ fmt(sello.alterados) }} expediente(s) con sello alterado. Revísalo en Actividad.</template>
        <template v-else-if="+sello.total === 0">Sello de integridad activo · aún no hay expedientes en la cadena</template>
        <template v-else>Integridad verificada · {{ fmt(sello.total) }} expedientes encadenados, sin alteraciones</template>
      </span>
    </div>

    <!-- Avance por municipio (alcance amplio) -->
    <div v-if="scopeAmplio" class="card overflow-hidden">
      <div class="p-4 border-b border-line">
        <div class="flex items-center justify-between gap-3 mb-3 flex-wrap">
          <h3 class="font-serif font-bold text-[15px]">Avance por municipio</h3>
          <div class="flex items-center gap-3">
            <input v-model="terrFQ" class="inp !w-40 !py-1.5 text-xs" placeholder="Buscar municipio…">
            <label class="flex items-center gap-1.5 text-[11px] font-semibold text-mut cursor-pointer whitespace-nowrap"><input type="checkbox" v-model="terrSinAct" class="accent-fp-600"> Sin actividad</label>
          </div>
        </div>

        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">Ámbito</div>
            <select v-model="terrAmbito" class="inp !w-full !py-1.5 text-xs truncate" @change="setAmbito">
              <option value="">Todos</option>
              <option value="nacional">Nacional</option>
              <option value="oclee">Exterior (OCLEE)</option>
            </select>
          </div>
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">Región</div>
            <select v-model="terrFRegion" class="inp !w-full !py-1.5 text-xs truncate" :disabled="!esNacional" @change="setRegion">
              <option value="">Todas</option>
              <option v-for="r in regionesF" :key="r" :value="r">{{ r }}</option>
            </select>
          </div>
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">Provincia</div>
            <select v-model.number="terrFProv" class="inp !w-full !py-1.5 text-xs truncate" :disabled="esExterior" @change="setProv">
              <option value="">{{ esExterior ? 'No aplica' : 'Todas' }}</option>
              <option v-for="p in provsOf(terrFRegion)" :key="p.id" :value="p.id">{{ p.nombre }}</option>
            </select>
          </div>
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">{{ esExterior ? 'Oficina OCLEE' : 'Municipio' }}</div>
            <select v-model.number="munF" class="inp !w-full !py-1.5 text-xs truncate">
              <option :value="0">Todos</option>
              <option v-for="m in munPadres(terrAmbito, terrFRegion, terrFProv)" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}</option>
            </select>
          </div>
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">Distrito</div>
            <select v-model.number="distF" class="inp !w-full !py-1.5 text-xs truncate" :disabled="!munF || esOclee || dists.length < 2">
              <option :value="0">{{ !verDistritos ? 'Desglose no habilitado' : (!munF ? 'Elige municipio' : (esOclee ? 'No aplica' : (distBusy ? 'Cargando…' : (dists.length < 2 ? 'Sin distritos' : 'Todos (' + dists.length + ')')))) }}</option>
              <option v-for="d in dists" :key="d.jce_id" :value="d.jce_id">{{ d.distrito }}{{ d.es_dm ? ' · DM' : '' }}</option>
            </select>
          </div>
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-wider text-mut mb-1">Circunscripción</div>
            <select v-model.number="circF" class="inp !w-full !py-1.5 text-xs truncate" :disabled="!munF || circs.length < 2">
              <option :value="0">{{ !munF ? 'Elige municipio' : (circs.length < 2 ? 'No dividido' : 'Todas (' + circs.length + ')') }}</option>
              <option v-for="c in circs" :key="c.circ_id" :value="c.circ_id">{{ c.nombre }}</option>
            </select>
          </div>
        </div>
      </div>
      <div class="px-4 py-3 border-b border-line bg-paper/60">
        <div class="flex items-baseline justify-between gap-3 mb-2 flex-wrap">
          <div class="text-[11px] font-bold uppercase tracking-wider text-mut">Totales del filtro</div>
          <div class="text-[12.5px] font-serif font-bold text-fp-800">{{ nivelTxt }}</div>
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-8 gap-2">
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Territorios</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.municipios ?? 0) }}</div>
            <div v-if="kf?.pendientes" class="text-[9.5px] text-amber-700">{{ fmt(kf.pendientes) }} pendientes JCE</div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Recintos</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.recintos ?? 0) }}</div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Colegios</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.colegios ?? 0) }}</div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Electores</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.electores ?? 0) }}</div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Meta</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.meta ?? 0) }}</div>
          </div>
          <div class="rounded-lg border border-fp-200 bg-fp-25 px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-fp-700">Registrados</div>
            <div class="text-[16px] font-bold tabular-nums text-fp-800">{{ fmt(kf?.registrados ?? 0) }}<span class="text-[11px] font-normal text-mut"> · {{ pctKf }}%</span></div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Colegios ✓</div>
            <div class="text-[16px] font-bold tabular-nums">{{ fmt(kf?.completos ?? 0) }}</div>
          </div>
          <div class="rounded-lg border border-line bg-white px-2.5 py-2">
            <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Faltan</div>
            <div class="text-[16px] font-bold tabular-nums text-amber-700">{{ fmt((kf?.parciales ?? 0) + (kf?.vacios ?? 0)) }}</div>
          </div>
        </div>
        <div class="text-[10.5px] text-mut mt-1.5">
          {{ fmt(kf?.parciales ?? 0) }} colegios incompletos · {{ fmt(kf?.vacios ?? 0) }} sin ningún registro<span v-if="kfBusy"> · actualizando…</span>
        </div>
      </div>
      <!-- Móvil: tarjetas de municipio -->
      <div class="sm:hidden">
        <div v-for="tr in terrViewF" :key="'m' + tr.municipio_id"
             class="px-4 py-3 border-b border-line/60 active:bg-fp-25/60" @click="irTerritorio(tr)">
          <div class="flex items-center justify-between gap-2 mb-1">
            <span class="font-semibold text-[13.5px] truncate">{{ tr.municipio }}
              <span v-if="tr.tipo === 'OCLEE'" class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">OCLEE</span>
              <span v-if="!tr.meta" class="badge border-amber-200 bg-amber-50 text-amber-800 ml-1">Pendiente JCE</span>
            </span>
            <span class="text-[13px] font-bold tabular-nums shrink-0"
                  :class="tr.pct >= 60 ? 'text-fp-700' : (tr.pct >= 25 ? 'text-amber-700' : 'text-mut')">{{ tr.pct }}%</span>
          </div>
          <div class="h-1.5 rounded-full bg-fp-50 overflow-hidden mb-1.5">
            <div class="h-full bar-anim" :class="semColor(tr.pct)" :style="{ width: Math.min(tr.pct, 100) + '%' }"></div>
          </div>
          <div class="flex items-center gap-3 text-[11.5px] text-mut">
            <span class="tabular-nums">{{ fmt(tr.total) }} / {{ fmt(tr.meta) }}</span>
            <span v-if="cobDe(tr.municipio_id)" class="tabular-nums">{{ fmt(cobDe(tr.municipio_id).completos) }} de {{ fmt(cobDe(tr.municipio_id).colegios) }} colegios</span>
            <span class="ml-auto truncate">{{ tr.provincia }}</span>
          </div>
        </div>
        <div v-if="!terrViewF.length && !terrBusy" class="px-4 py-8 text-center text-mut text-[13px]">Sin municipios que coincidan con el filtro.</div>
        <div v-if="terrBusy" class="px-4 py-8 text-center text-mut text-[13px]">Cargando municipios…</div>
      </div>

      <div class="hidden sm:block overflow-x-auto">
        <table class="w-full min-w-[720px]">
          <thead class="bg-paper border-b border-line">
            <tr>
              <th class="th cursor-pointer" @click="terrOrden('municipio')">Municipio {{ tArrow('municipio') }}</th>
              <th class="th cursor-pointer" @click="terrOrden('provincia')">Provincia {{ tArrow('provincia') }}</th>
              <th class="th cursor-pointer text-right" @click="terrOrden('meta')">Meta {{ tArrow('meta') }}</th>
              <th class="th cursor-pointer text-right" @click="terrOrden('total')">Registrados {{ tArrow('total') }}</th>
              <th class="th text-center">Colegios ✓</th>
              <th class="th cursor-pointer w-40" @click="terrOrden('pct')">Avance {{ tArrow('pct') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tr in terrViewF" :key="tr.municipio_id" class="border-b border-line/70 hover:bg-fp-25/60 cursor-pointer" @click="irTerritorio(tr)">
              <td class="td font-semibold">{{ tr.municipio }}
                <span v-if="tr.tipo === 'OCLEE'" class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">OCLEE</span>
                <span v-if="!tr.meta" class="badge border-amber-200 bg-amber-50 text-amber-800 ml-1" title="Sus colegios aún no están en la carga de datos de la JCE">Pendiente de carga JCE</span>
              </td>
              <td class="td text-mut">{{ tr.provincia }}</td>
              <td class="td text-right tabular-nums">{{ fmt(tr.meta) }}</td>
              <td class="td text-right tabular-nums font-semibold">{{ fmt(tr.total) }}</td>
              <td class="td text-center tabular-nums text-[12px]">
                <template v-if="cobDe(tr.municipio_id)">
                  <b :class="+cobDe(tr.municipio_id).completos === +cobDe(tr.municipio_id).colegios && +cobDe(tr.municipio_id).colegios > 0 ? 'text-fp-700' : ''">{{ fmt(cobDe(tr.municipio_id).completos) }}</b><span class="text-mut"> / {{ fmt(cobDe(tr.municipio_id).colegios) }}</span>
                </template>
                <span v-else class="text-mut/50">—</span>
              </td>
              <td class="td">
                <div class="flex items-center gap-2">
                  <div class="flex-1 h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bar-anim" :class="semColor(tr.pct)" :style="{ width: Math.min(tr.pct, 100) + '%' }"></div></div>
                  <span class="text-[11px] tabular-nums w-9 text-right" :class="tr.pct >= 60 ? 'text-fp-700 font-bold' : (tr.pct >= 25 ? 'text-amber-700 font-semibold' : 'text-mut')">{{ tr.pct }}%</span>
                </div>
              </td>
            </tr>
            <tr v-if="!terrViewF.length && !terrBusy"><td colspan="6" class="td text-center text-mut py-8">Sin municipios que coincidan con el filtro.</td></tr>
            <tr v-if="terrBusy"><td colspan="6" class="td text-center text-mut py-8">Cargando municipios…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
        {{ terrViewF.length }} territorios · {{ terrSinAct ? terrViewF.length : sinActF }} sin actividad · elige uno para ver sus distritos y colegios
        <span v-if="pendientesJCE" class="block mt-1 text-amber-700">
          {{ pendientesJCE }} con la etiqueta <b>Pendiente de carga JCE</b>: figuran en el listado, pero sus colegios llegarán con la próxima actualización de datos de la Junta.
        </span>
      </div>
    </div>

    <!-- AVANCE POR DISTRITO del municipio elegido / propio -->
    <div v-if="munEfectivo && !esOclee && (scopeAmplio || verDistritos)" class="card overflow-hidden">
      <div class="p-4 border-b border-line flex flex-wrap items-center gap-2">
        <h3 class="font-serif font-bold text-[15px] mr-auto">
          Avance por distrito · {{ catMap.get(munEfectivo)?.nombre || perfil?.municipio || '' }}
        </h3>
        <select v-if="!scopeAmplio" v-model.number="distF" class="inp !w-auto !py-1.5 text-xs" :disabled="distBusy">
          <option :value="0">Todos los distritos ({{ dists.length }})</option>
          <option v-for="d in dists" :key="d.jce_id" :value="d.jce_id">{{ d.distrito }}{{ d.es_dm ? ' · DM' : '' }}</option>
        </select>
        <select v-if="!scopeAmplio && circs.length" v-model.number="circF" class="inp !w-auto !py-1.5 text-xs">
          <option :value="0">Todas las circunscripciones ({{ circs.length }})</option>
          <option v-for="c in circs" :key="c.circ_id" :value="c.circ_id">{{ c.nombre }}</option>
        </select>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[640px]">
          <thead class="bg-paper border-b border-line">
            <tr>
              <th class="th">Distrito / Demarcación</th>
              <th class="th text-right">Colegios</th>
              <th class="th text-right">Meta</th>
              <th class="th text-right">Registrados</th>
              <th class="th text-center">Colegios ✓</th>
              <th class="th w-36">Avance</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="d in dists" :key="d.jce_id"
                class="border-b border-line/70 cursor-pointer hover:bg-fp-25/60"
                :class="distF === d.jce_id ? 'bg-fp-25' : ''"
                @click="distF = (distF === d.jce_id ? 0 : d.jce_id)">
              <td class="td font-semibold">{{ d.distrito }}
                <span v-if="d.es_dm" class="badge border-line bg-paper text-mut ml-1">DM</span>
                <span v-else class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">Cabecera</span>
              </td>
              <td class="td text-right tabular-nums">{{ fmt(d.colegios) }}</td>
              <td class="td text-right tabular-nums">{{ fmt(d.meta) }}</td>
              <td class="td text-right tabular-nums font-semibold">{{ fmt(d.total) }}</td>
              <td class="td text-center tabular-nums text-[12px]"><b :class="+d.completos === +d.colegios && +d.colegios > 0 ? 'text-fp-700' : ''">{{ fmt(d.completos) }}</b><span class="text-mut"> / {{ fmt(d.colegios) }}</span></td>
              <td class="td">
                <div class="flex items-center gap-2">
                  <div class="flex-1 h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bar-anim" :class="semColor(pctD(d))" :style="{ width: Math.min(pctD(d), 100) + '%' }"></div></div>
                  <span class="text-[11px] tabular-nums w-9 text-right">{{ pctD(d) }}%</span>
                </div>
              </td>
            </tr>
            <tr v-if="!dists.length && !distBusy"><td colspan="6" class="td text-center text-mut py-6">Este municipio no tiene distritos registrados en la estructura JCE.</td></tr>
            <tr v-if="distBusy"><td colspan="6" class="td text-center text-mut py-6">Cargando distritos…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
        {{ dists.length }} demarcación(es) · toca una fila para ver solo sus colegios abajo

      </div>
    </div>

    <CoberturaColegios v-if="munEfectivo" :municipio-id="munEfectivo" :jce-id="distF" :circ-id="circF" :titulo="tituloCob" />

    <div class="grid lg:grid-cols-2 gap-4">
      <div class="card p-4">
        <h3 class="font-serif font-bold text-[15px] mb-3">Por etapa del proceso</h3>
        <div v-if="!estadoBars.length" class="text-sm text-mut py-4 text-center">Aún no hay registros.</div>
        <div v-for="b in estadoBars" :key="b.k" class="mb-2.5">
          <div class="flex justify-between text-[12px] mb-1"><span class="font-medium">{{ estadoLbl[b.k] || b.k }}</span><span class="text-mut">{{ fmt(b.n) }}</span></div>
          <div class="h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bg-fp-600/80 bar-anim" :style="{ width: b.pct + '%' }"></div></div>
        </div>
      </div>
      <div class="card p-4">
        <h3 class="font-serif font-bold text-[15px] mb-3">Por cargo postulado</h3>
        <div v-if="!cargoBars.length" class="text-sm text-mut py-4 text-center">Aún no hay registros.</div>
        <div v-for="b in cargoBars" :key="b.k" class="mb-2.5">
          <div class="flex justify-between text-[12px] mb-1"><span class="font-medium">{{ cargoLbl[b.k] || b.k }}</span><span class="text-mut">{{ fmt(b.n) }}</span></div>
          <div class="h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bg-fp-400 bar-anim" :style="{ width: b.pct + '%' }"></div></div>
        </div>
      </div>
    </div>
  </section>
</template>
