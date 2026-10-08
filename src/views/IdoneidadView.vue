<!-- src/views/IdoneidadView.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { sb } from '../lib/supabase';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';
import { cargoLbl, reqLbl, reqPeso } from '../lib/constantes';
import { catMap, regiones, provsOf } from '../stores/catalogo';

const filas = ref([]), cargando = ref(true), err = ref('');
const f = ref({ q: '', ambito: '', region: '', prov: '', mun: '', cargo: '', franja: '', fuera: '' });

const cargar = async () => {
  cargando.value = true; err.value = '';
  const { data, error } = await sb.rpc('portal_idoneidad', {
    p_ambito:    f.value.ambito || null,
    p_region:    f.value.region || null,
    p_provincia: f.value.prov || null,
    p_municipio: f.value.mun || null,
    p_jce:       null
  });
  cargando.value = false;
  if (error) {
    err.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase50_requisitos_y_experiencia.sql en Supabase.'
      : 'No se pudo cargar: ' + error.message;
    return;
  }
  filas.value = data || [];
};
onMounted(cargar);

const franjas = [
  { k: 'alto',  t: 'Perfil alto',  d: '80% o más', min: 80, max: 101, cls: 'border-fp-600 bg-fp-600 text-white' },
  { k: 'medio', t: 'Perfil medio', d: 'entre 50 y 79%', min: 50, max: 80, cls: 'border-amber-300 bg-amber-50 text-amber-800' },
  { k: 'bajo',  t: 'Perfil bajo',  d: 'menos de 50%', min: 0, max: 50, cls: 'border-red-200 bg-red-50 text-red-700' }
];
const franjaDe = r => franjas.find(x => r.pct >= x.min && r.pct < x.max) || franjas[2];

const vista = computed(() => {
  const q = f.value.q.trim().toLowerCase();
  return filas.value.filter(r => {
    if (q && !String(r.nombre).toLowerCase().includes(q) && !String(r.cedula).includes(q)) return false;
    if (f.value.cargo && r.cargo !== f.value.cargo) return false;
    if (f.value.franja && franjaDe(r).k !== f.value.franja) return false;
    if (f.value.fuera === 'si' && !r.fuera_de_colegio) return false;
    if (f.value.fuera === 'no' && r.fuera_de_colegio) return false;
    return true;
  });
});

const res = computed(() => {
  const l = vista.value, n = l.length || 1;
  return {
    total: l.length,
    alto: l.filter(r => franjaDe(r).k === 'alto').length,
    medio: l.filter(r => franjaDe(r).k === 'medio').length,
    bajo: l.filter(r => franjaDe(r).k === 'bajo').length,
    media: Math.round(l.reduce((a, r) => a + r.pct, 0) / n),
    firmados: l.filter(r => r.firmado).length,
    fuera: l.filter(r => r.fuera_de_colegio).length,
    conExp: l.filter(r => r.experiencia > 0).length
  };
});

const muns = computed(() => [...catMap.value.values()]
  .filter(m => (!f.value.prov || m.provincia_id === f.value.prov)
            && (!f.value.region || m.macroregion === f.value.region)
            && (!f.value.ambito || f.value.ambito === 'todos'
                || (f.value.ambito === 'oclee') === (m.tipo === 'OCLEE')))
  .sort((a, b) => String(a.nombre).localeCompare(String(b.nombre))));

const provs = computed(() => provsOf(f.value.region || ''));

const exportar = () => {
  sb.rpc('portal_log_exportacion', { p_tipo: 'idoneidad_csv', p_registros: vista.value.length }).then(() => {}, () => {});
  const h = ['Formulario','Cédula','Nombre','Cargo','Ámbito','Región','Provincia','Municipio','Distrito','Puntos','Máximo','%','Requisitos','Experiencia','Firmado','Colegio'];
  const esc = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = [h.map(esc).join(',')].concat(vista.value.map(r =>
    [r.numero_formulario, r.cedula, r.nombre, cargoLbl[r.cargo] || r.cargo,
     r.puntos, r.maximo, r.pct + '%', `${r.requisitos_ok}/${r.requisitos_total}`,
     r.experiencia, r.firmado ? 'Sí' : 'No'].map(esc).join(','))).join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `idoneidad-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  t('Archivo descargado', 'ok');
};

const pesosOrden = computed(() => Object.entries(reqPeso).sort((a, b) => b[1] - a[1]));
const verPesos = ref(false);
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <div class="mr-auto">
        <h2 class="font-serif font-bold text-[22px]">Análisis de idoneidad</h2>
        <p class="text-[12.5px] text-mut">Perfil de los postulantes según los requisitos certificados</p>
      </div>
      <button class="btn-o btn-s" @click="verPesos = !verPesos">{{ verPesos ? 'Ocultar' : '⚖ Ver' }} matriz de peso</button>
      <button class="btn-o btn-s" @click="exportar" :disabled="!vista.length">⤓ CSV</button>
    </div>

    <div v-if="err" class="errbx">{{ err }}</div>

    <!-- Matriz de peso -->
    <div v-if="verPesos" class="card p-4">
      <h3 class="font-serif font-bold text-[15px] mb-1">Cómo se calcula</h3>
      <p class="text-[12px] text-mut mb-3 max-w-[74ch]">
        No todos los requisitos pesan igual. Los tres esenciales —militancia, derechos políticos e
        inscripción en la demarcación— valen 3 puntos, porque sin ellos la persona no puede ejercer.
        Los demás valen 2. El máximo es {{ Object.values(reqPeso).reduce((a,b)=>a+b,0) }} puntos.
      </p>
      <div class="grid sm:grid-cols-2 gap-x-6 gap-y-1.5">
        <div v-for="[k, w] in pesosOrden" :key="k" class="flex items-start gap-2.5 py-1 border-b border-line/50">
          <span class="badge shrink-0 mt-0.5" :class="w === 3 ? 'border-fp-600 bg-fp-600 text-white' : 'border-line bg-paper text-mut'">{{ w }}</span>
          <span class="text-[12px] leading-snug">{{ reqLbl[k] }}</span>
        </div>
      </div>
    </div>

    <!-- Resumen -->
    <div class="grid grid-cols-2 lg:grid-cols-5 gap-3">
      <div class="rounded-xl bg-fp-700 text-white px-4 py-3">
        <div class="text-[11px] text-fp-100/85">Idoneidad media</div>
        <div class="text-[26px] font-bold tabular-nums leading-tight">{{ res.media }}%</div>
        <div class="text-[11px] text-fp-100/85">{{ fmt(res.total) }} postulantes</div>
      </div>
      <button v-for="fr in franjas" :key="fr.k"
              class="rounded-xl px-4 py-3 text-left border transition-colors"
              :class="f.franja === fr.k ? 'bg-white border-fp-400' : 'bg-paper border-transparent hover:border-line'"
              @click="f.franja = f.franja === fr.k ? '' : fr.k">
        <div class="text-[11px] text-mut">{{ fr.t }}</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight"
             :class="fr.k === 'alto' ? 'text-fp-700' : (fr.k === 'medio' ? 'text-amber-700' : 'text-red-700')">
          {{ fmt(res[fr.k]) }}
        </div>
        <div class="text-[10.5px] text-mut">{{ fr.d }}</div>
      </button>
      <button class="rounded-xl px-4 py-3 text-left border transition-colors"
              :class="f.fuera === 'si' ? 'bg-white border-red-300' : 'bg-paper border-transparent hover:border-line'"
              @click="f.fuera = f.fuera === 'si' ? '' : 'si'">
        <div class="text-[11px] text-mut">Fuera de su demarcación</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight" :class="res.fuera ? 'text-red-700' : ''">{{ fmt(res.fuera) }}</div>
        <div class="text-[10.5px] text-mut">{{ fmt(res.conExp) }} con experiencia · {{ fmt(res.firmados) }} firmados</div>
      </button>
    </div>

    <!-- Filtros -->
    <div class="card p-3 grid sm:grid-cols-2 lg:grid-cols-4 gap-2">
      <input v-model="f.q" class="inp !py-2 text-[13px]" placeholder="Buscar nombre o cédula…">

      <select v-model="f.ambito" class="inp !py-2 text-[13px]"
              @change="f.region=''; f.prov=''; f.mun=''; cargar()">
        <option value="">Ámbito: todo</option>
        <option value="nacional">Nacional</option>
        <option value="oclee">Exterior · OCLEE</option>
      </select>

      <select v-model="f.region" class="inp !py-2 text-[13px]"
              @change="f.prov=''; f.mun=''; cargar()">
        <option value="">Región: todas</option>
        <option v-for="r in regiones" :key="r" :value="r">{{ r }}</option>
      </select>

      <select v-model.number="f.prov" class="inp !py-2 text-[13px]"
              @change="f.mun=''; cargar()">
        <option value="">Provincia: todas</option>
        <option v-for="p in provs" :key="p.id" :value="p.id">{{ p.nombre }}</option>
      </select>

      <select v-model.number="f.mun" class="inp !py-2 text-[13px]" @change="cargar">
        <option value="">Municipio: todos</option>
        <option v-for="m in muns" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}</option>
      </select>

      <select v-model="f.cargo" class="inp !py-2 text-[13px]">
        <option value="">Cargo: todos</option>
        <option v-for="(v, k) in cargoLbl" :key="k" :value="k">{{ v }}</option>
      </select>

      <select v-model="f.fuera" class="inp !py-2 text-[13px]">
        <option value="">Colegio: todos</option>
        <option value="no">En su propio colegio</option>
        <option value="si">Fuera de su demarcación</option>
      </select>

      <button class="btn-o !py-2" @click="f = { q:'', ambito:'', region:'', prov:'', mun:'', cargo:'', franja:'', fuera:'' }; cargar()">Limpiar</button>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

    <div v-else class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[860px]">
          <thead class="bg-paper border-b border-line"><tr>
            <th class="th">Postulante</th><th class="th">Cargo</th>
            <th class="th w-[190px]">Idoneidad</th>
            <th class="th text-center">Requisitos</th>
            <th class="th text-center">Experiencia</th>
            <th class="th text-center">Firmado</th>
          </tr></thead>
          <tbody>
            <tr v-for="r in vista" :key="r.id" class="border-b border-line/60">
              <td class="td">
                <div class="font-semibold text-[13px]">{{ r.nombre }}</div>
                <div class="text-[11px] text-mut tabular-nums">
                  {{ r.numero_formulario }}<span v-if="r.colegio"> · Colegio {{ r.colegio }}</span>
                </div>
                <div class="text-[10.5px] text-mut flex flex-wrap items-center gap-1.5 mt-0.5">
                  <span>{{ [r.distrito, r.municipio].filter(Boolean).join(' · ') }}</span>
                  <span v-if="r.fuera_de_colegio" class="badge border-red-300 bg-red-50 text-red-700"
                        title="Vota en otra demarcación">⚠ Fuera de su demarcación</span>
                </div>
              </td>
              <td class="td text-[12.5px] whitespace-nowrap">{{ cargoLbl[r.cargo] || r.cargo }}</td>
              <td class="td">
                <div class="flex items-center gap-2">
                  <div class="h-2 flex-1 rounded-full bg-paper overflow-hidden">
                    <div class="h-full rounded-full"
                         :class="franjaDe(r).k === 'alto' ? 'bg-fp-600' : (franjaDe(r).k === 'medio' ? 'bg-amber-400' : 'bg-red-400')"
                         :style="{ width: r.pct + '%' }"></div>
                  </div>
                  <span class="text-[12px] font-bold tabular-nums w-11 text-right">{{ r.pct }}%</span>
                </div>
                <div class="text-[10.5px] text-mut mt-0.5 tabular-nums">{{ r.puntos }} de {{ r.maximo }} puntos</div>
              </td>
              <td class="td text-center text-[12.5px] tabular-nums">{{ r.requisitos_ok }}/{{ r.requisitos_total }}</td>
              <td class="td text-center text-[12.5px] tabular-nums">{{ r.experiencia || '—' }}</td>
              <td class="td text-center">
                <span v-if="r.firmado" class="badge border-fp-600 bg-fp-600 text-white">Sí</span>
                <span v-else class="text-mut text-[12px]">—</span>
              </td>
            </tr>
            <tr v-if="!vista.length"><td colspan="6" class="td text-center text-mut py-10">Sin postulantes que coincidan.</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
        {{ fmt(vista.length) }} postulantes · ordenados de mayor a menor idoneidad
      </div>
    </div>
  </section>
</template>
