<!-- src/views/AvanceView.vue · Avance por territorio, solo cifras (fase 82) -->
<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { sb } from '../lib/supabase';
import { perfil, verDistritos } from '../stores/auth';
import { catMap } from '../stores/catalogo';
import { semColor } from '../stores/kpi';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';
import CoberturaColegios from '../components/CoberturaColegios.vue';

/* ── Nivel de partida según el alcance del usuario ── */
const nivelBase = computed(() => {
  const p = perfil.value || {};
  if (['admin_sne', 'consulta_nacional'].includes(p.rol)) return 'nacional';
  if (p.rol === 'coordinador_regional') return 'region';
  if (p.rol === 'supervisor_provincial' || (!p.municipio_id && p.provincia_id)) return 'provincia';
  return 'municipio';
});

const sel = ref({ region: '', prov: 0, mun: 0, dist: 0 });
const partida = () => {
  const p = perfil.value || {};
  sel.value = {
    region: nivelBase.value === 'region' ? (p.region || '') : '',
    prov:   nivelBase.value === 'provincia' ? (p.provincia_id || 0) : 0,
    mun:    nivelBase.value === 'municipio' ? (p.municipio_id || 0) : 0,
    dist: 0
  };
};

/* ── Datos: municipios con avance y cobertura (la base limita al alcance) ── */
const filas = ref([]);
const busy = ref(false);
const cargar = async () => {
  busy.value = true;
  const [k, c] = await Promise.all([sb.rpc('portal_kpi_territorios'), sb.rpc('portal_cobertura_resumen')]);
  busy.value = false;
  if (k.error) { t('Avance: ' + k.error.message, 'err'); return; }
  const cob = new Map((c.data || []).map(r => [r.municipio_id, r]));
  filas.value = (k.data || []).map(r => {
    const cb = cob.get(r.municipio_id) || {};
    const meta = Number(r.meta || 0), total = Number(r.total || 0);
    return {
      ...r, meta, total, colegios: Number(r.colegios || 0),
      completos: Number(cb.completos || 0), parciales: Number(cb.parciales || 0), vacios: Number(cb.vacios || 0),
      regionK: r.macroregion || (r.tipo === 'OCLEE' ? 'Exterior (OCLEE)' : 'Sin región'),
      provK:   r.provincia_id || (r.tipo === 'OCLEE' ? 'oclee' : 'sin'),
      provN:   r.provincia || (r.tipo === 'OCLEE' ? 'Oficinas OCLEE' : 'Sin provincia')
    };
  });
};
onMounted(() => { partida(); cargar(); });
watch(perfil, () => { partida(); cargar(); });

/* ── Nivel actual y filas del nivel ── */
const nivel = computed(() => sel.value.mun ? 'municipio' : (sel.value.prov ? 'provincia' : (sel.value.region ? 'region' : 'nacional')));
const enAlcance = computed(() => filas.value.filter(r =>
  (!sel.value.region || r.regionK === sel.value.region) && (!sel.value.prov || r.provK === sel.value.prov)));

const sumar = (lista, keyFn, nombreFn) => {
  const g = new Map();
  lista.forEach(r => {
    const k = keyFn(r);
    const a = g.get(k) || { key: k, nombre: nombreFn(r), n: 0, colegios: 0, meta: 0, total: 0, completos: 0, parciales: 0, vacios: 0, tipo: r.tipo };
    a.n++; a.colegios += r.colegios; a.meta += r.meta; a.total += r.total;
    a.completos += r.completos; a.parciales += r.parciales; a.vacios += r.vacios;
    g.set(k, a);
  });
  return [...g.values()];
};
const conAvance = a => ({ ...a, pct: a.meta ? Math.round(a.total * 100 / a.meta) : 0, faltan: Math.max(a.meta - a.total, 0), incompletos: a.parciales + a.vacios });

const soloInc = ref(false);
const orden = ref('pct');
const q = ref('');
const filasNivel = computed(() => {
  let l;
  if (nivel.value === 'nacional')  l = sumar(enAlcance.value, r => r.regionK, r => r.regionK);
  else if (nivel.value === 'region') l = sumar(enAlcance.value, r => r.provK, r => r.provN);
  else l = enAlcance.value.map(r => ({ ...r, key: r.municipio_id, nombre: r.municipio, n: 1 }));
  l = l.map(conAvance);
  if (soloInc.value) l = l.filter(r => r.pct < 100);
  if (q.value.trim()) { const s = q.value.trim().toLowerCase(); l = l.filter(r => String(r.nombre || '').toLowerCase().includes(s)); }
  l.sort((a, b) => orden.value === 'nombre' ? String(a.nombre).localeCompare(String(b.nombre))
                 : orden.value === 'faltan' ? (b.faltan - a.faltan) || String(a.nombre).localeCompare(String(b.nombre))
                 : (a.pct - b.pct) || (b.faltan - a.faltan) || String(a.nombre).localeCompare(String(b.nombre)));
  return l;
});
const totales = computed(() => conAvance(sumar(enAlcance.value, () => 1, () => '')[0] || { n: 0, colegios: 0, meta: 0, total: 0, completos: 0, parciales: 0, vacios: 0 }));

const entrar = r => {
  if (nivel.value === 'nacional') sel.value.region = r.key;
  else if (nivel.value === 'region') sel.value.prov = r.key;
  else { sel.value.mun = r.key; sel.value.dist = 0; }
};
const irA = n => {
  if (n === 'nacional' && nivelBase.value === 'nacional') sel.value = { region: '', prov: 0, mun: 0, dist: 0 };
  if (n === 'region')    sel.value = { ...sel.value, prov: 0, mun: 0, dist: 0 };
  if (n === 'provincia') sel.value = { ...sel.value, mun: 0, dist: 0 };
  if (n === 'municipio') sel.value.dist = 0;
};
const puedeSubir = n => ({ nacional: 0, region: 1, provincia: 2, municipio: 3 })[n] >= ({ nacional: 0, region: 1, provincia: 2, municipio: 3 })[nivelBase.value];
const nombreProv = computed(() => filas.value.find(r => r.provK === sel.value.prov)?.provN || perfil.value?.provincia || '');
const munObj = computed(() => catMap.value.get(sel.value.mun) || filas.value.find(r => r.municipio_id === sel.value.mun) || null);
const munNombre = computed(() => munObj.value?.nombre || munObj.value?.municipio || perfil.value?.municipio || '');
const esOclee = computed(() => (munObj.value?.tipo || perfil.value?.tipo_territorio) === 'OCLEE');
const nivelLbl = { nacional: 'Regiones', region: 'Provincias', provincia: 'Municipios' };
const unidadLbl = { nacional: 'regiones', region: 'provincias', provincia: 'municipios' };

/* ── Municipio: distritos y colegios ── */
const dists = ref([]);
const distBusy = ref(false);
const cargarDists = async id => {
  dists.value = []; if (!id || esOclee.value || !verDistritos.value) return;
  distBusy.value = true;
  const { data, error } = await sb.rpc('portal_kpi_distritos', { p_municipio: id });
  distBusy.value = false;
  if (error) { t('Distritos: ' + error.message, 'err'); return; }
  dists.value = (data || []).map(d => ({ ...d, pct: Number(d.meta) ? Math.round(Number(d.total) * 100 / Number(d.meta)) : 0, faltan: Math.max(Number(d.meta) - Number(d.total), 0) }));
};
watch(() => sel.value.mun, cargarDists, { immediate: true });
const distNombre = computed(() => dists.value.find(d => d.jce_id === sel.value.dist)?.distrito || '');
const tituloCob = computed(() => 'Colegios · ' + munNombre.value + (distNombre.value ? ' · ' + distNombre.value : ''));
</script>

<template>
  <section class="space-y-4">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <div>
        <h2 class="font-serif font-bold text-[22px] leading-tight">Avance</h2>
        <p class="text-[12.5px] text-mut mt-0.5">Cifras por territorio: cuánto se ha registrado, cuántos colegios están completos y cuánto falta. Sin nombres de personas.</p>
      </div>
      <button class="btn-p btn-s" :disabled="busy" @click="cargar">{{ busy ? 'Actualizando…' : 'Actualizar' }}</button>
    </div>

    <!-- Ruta de niveles -->
    <div class="flex items-center gap-1.5 text-[12.5px] flex-wrap">
      <button v-if="puedeSubir('nacional')" class="font-semibold" :class="nivel === 'nacional' ? 'text-ink' : 'text-fp-700 hover:underline'" @click="irA('nacional')">Nacional</button>
      <template v-if="sel.region"><span class="text-mut">›</span>
        <button class="font-semibold" :class="nivel === 'region' ? 'text-ink' : 'text-fp-700 hover:underline'" @click="irA('region')">Región {{ sel.region }}</button></template>
      <template v-if="sel.prov"><span class="text-mut">›</span>
        <button class="font-semibold" :class="nivel === 'provincia' ? 'text-ink' : 'text-fp-700 hover:underline'" @click="irA('provincia')">{{ nombreProv }}</button></template>
      <template v-if="sel.mun"><span class="text-mut">›</span>
        <button class="font-semibold" :class="!sel.dist ? 'text-ink' : 'text-fp-700 hover:underline'" @click="irA('municipio')">{{ munNombre }}</button></template>
      <template v-if="sel.dist"><span class="text-mut">›</span><span class="font-semibold">{{ distNombre }}</span></template>
    </div>

    <!-- Totales del nivel -->
    <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-2">
      <div v-if="nivel !== 'municipio'" class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Municipios</div>
        <div class="text-[16px] font-bold tabular-nums">{{ fmt(totales.n) }}</div>
      </div>
      <div class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Colegios</div>
        <div class="text-[16px] font-bold tabular-nums">{{ fmt(totales.colegios) }}</div>
      </div>
      <div class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Meta</div>
        <div class="text-[16px] font-bold tabular-nums">{{ fmt(totales.meta) }}</div>
      </div>
      <div class="rounded-lg border border-fp-200 bg-fp-25 px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-fp-700">Registrados</div>
        <div class="text-[16px] font-bold tabular-nums text-fp-800">{{ fmt(totales.total) }}<span class="text-[11px] font-normal text-mut"> · {{ totales.pct }}%</span></div>
      </div>
      <div class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Colegios ✓</div>
        <div class="text-[16px] font-bold tabular-nums">{{ fmt(totales.completos) }}</div>
      </div>
      <div class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Incompletos</div>
        <div class="text-[16px] font-bold tabular-nums text-amber-700">{{ fmt(totales.incompletos) }}</div>
        <div class="text-[9.5px] text-mut">{{ fmt(totales.parciales) }} parciales · {{ fmt(totales.vacios) }} vacíos</div>
      </div>
      <div class="rounded-lg border border-line bg-white px-2.5 py-2">
        <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Faltan personas</div>
        <div class="text-[16px] font-bold tabular-nums text-red-700">{{ fmt(totales.faltan) }}</div>
      </div>
    </div>

    <!-- Tabla del nivel (regiones / provincias / municipios) -->
    <div v-if="nivel !== 'municipio'" class="card overflow-hidden">
      <div class="p-3 sm:p-4 border-b border-line flex flex-wrap items-center gap-2">
        <h3 class="font-serif font-bold text-[15px] mr-auto">{{ nivelLbl[nivel] }}</h3>
        <input v-model="q" class="inp !w-40 !py-1.5 text-xs" placeholder="Buscar…">
        <select v-model="orden" class="inp !w-auto !py-1.5 text-xs">
          <option value="pct">Menor avance primero</option>
          <option value="faltan">Más faltantes primero</option>
          <option value="nombre">Por nombre</option>
        </select>
        <label class="flex items-center gap-1.5 text-[11px] font-semibold text-mut cursor-pointer whitespace-nowrap"><input type="checkbox" v-model="soloInc" class="accent-fp-600"> Solo incompletos</label>
      </div>

      <!-- Móvil -->
      <div class="sm:hidden">
        <div v-for="r in filasNivel" :key="r.key" class="px-4 py-3 border-b border-line/60 active:bg-fp-25/60" @click="entrar(r)">
          <div class="flex items-center justify-between gap-2 mb-1">
            <span class="font-semibold text-[13.5px] truncate">{{ r.nombre }}<span v-if="r.tipo === 'OCLEE' && nivel === 'provincia'" class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">OCLEE</span></span>
            <span class="text-[13px] font-bold tabular-nums shrink-0" :class="r.pct >= 60 ? 'text-fp-700' : (r.pct >= 25 ? 'text-amber-700' : 'text-mut')">{{ r.pct }}%</span>
          </div>
          <div class="h-1.5 rounded-full bg-fp-50 overflow-hidden mb-1.5"><div class="h-full bar-anim" :class="semColor(r.pct)" :style="{ width: Math.min(r.pct, 100) + '%' }"></div></div>
          <div class="flex items-center gap-3 text-[11.5px] text-mut">
            <span class="tabular-nums">{{ fmt(r.total) }} / {{ fmt(r.meta) }}</span>
            <span class="tabular-nums">{{ fmt(r.completos) }} de {{ fmt(r.colegios) }} colegios</span>
            <span class="ml-auto tabular-nums text-red-700">faltan {{ fmt(r.faltan) }}</span>
          </div>
        </div>
      </div>

      <!-- Escritorio -->
      <div class="hidden sm:block overflow-x-auto">
        <table class="w-full min-w-[720px]">
          <thead class="bg-paper border-b border-line">
            <tr>
              <th class="th">{{ nivelLbl[nivel].replace(/s$/, '') }}</th>
              <th v-if="nivel !== 'provincia'" class="th text-right">Municipios</th>
              <th class="th text-right">Colegios</th>
              <th class="th text-right">Meta</th>
              <th class="th text-right">Registrados</th>
              <th class="th text-center">Colegios ✓</th>
              <th class="th text-center">Incompletos</th>
              <th class="th text-right">Faltan</th>
              <th class="th w-40">Avance</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in filasNivel" :key="r.key" class="border-b border-line/70 hover:bg-fp-25/60 cursor-pointer" @click="entrar(r)">
              <td class="td font-semibold">{{ r.nombre }}
                <span v-if="r.tipo === 'OCLEE' && nivel === 'provincia'" class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">OCLEE</span>
                <span v-if="!r.meta" class="badge border-amber-200 bg-amber-50 text-amber-800 ml-1" title="Sus colegios aún no están en la carga de datos de la JCE">Pendiente JCE</span>
              </td>
              <td v-if="nivel !== 'provincia'" class="td text-right tabular-nums">{{ fmt(r.n) }}</td>
              <td class="td text-right tabular-nums">{{ fmt(r.colegios) }}</td>
              <td class="td text-right tabular-nums">{{ fmt(r.meta) }}</td>
              <td class="td text-right tabular-nums font-semibold">{{ fmt(r.total) }}</td>
              <td class="td text-center tabular-nums text-[12px]"><b :class="r.completos === r.colegios && r.colegios > 0 ? 'text-fp-700' : ''">{{ fmt(r.completos) }}</b><span class="text-mut"> / {{ fmt(r.colegios) }}</span></td>
              <td class="td text-center tabular-nums text-[12px]"><span class="text-amber-700">{{ fmt(r.parciales) }}</span><span class="text-mut"> + </span><span class="text-red-700">{{ fmt(r.vacios) }}</span></td>
              <td class="td text-right tabular-nums text-red-700 font-semibold">{{ fmt(r.faltan) }}</td>
              <td class="td">
                <div class="flex items-center gap-2">
                  <div class="flex-1 h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bar-anim" :class="semColor(r.pct)" :style="{ width: Math.min(r.pct, 100) + '%' }"></div></div>
                  <span class="text-[11px] tabular-nums w-9 text-right" :class="r.pct >= 60 ? 'text-fp-700 font-bold' : (r.pct >= 25 ? 'text-amber-700 font-semibold' : 'text-mut')">{{ r.pct }}%</span>
                </div>
              </td>
            </tr>
            <tr v-if="!filasNivel.length && !busy"><td colspan="9" class="td text-center text-mut py-8">Sin territorios que coincidan.</td></tr>
            <tr v-if="busy"><td colspan="9" class="td text-center text-mut py-8">Cargando…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
        {{ filasNivel.length }} {{ unidadLbl[nivel] }} · Incompletos = colegios parciales (1 o 2 personas) + vacíos (ninguna) · elige una fila para bajar de nivel
      </div>
    </div>

    <!-- Municipio: distritos -->
    <div v-if="nivel === 'municipio' && !esOclee && verDistritos" class="card overflow-hidden">
      <div class="p-3 sm:p-4 border-b border-line flex flex-wrap items-center gap-2">
        <h3 class="font-serif font-bold text-[15px] mr-auto">Distritos · {{ munNombre }}</h3>
        <span class="text-[11px] text-mut">toca un distrito para ver solo sus colegios abajo</span>
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
              <th class="th text-center">Incompletos</th>
              <th class="th text-right">Faltan</th>
              <th class="th w-36">Avance</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="d in dists" :key="d.jce_id" class="border-b border-line/70 cursor-pointer hover:bg-fp-25/60" :class="sel.dist === d.jce_id ? 'bg-fp-25' : ''"
                @click="sel.dist = (sel.dist === d.jce_id ? 0 : d.jce_id)">
              <td class="td font-semibold">{{ d.distrito }}
                <span v-if="d.es_dm" class="badge border-line bg-paper text-mut ml-1">DM</span>
                <span v-else class="badge border-fp-200 bg-fp-50 text-fp-800 ml-1">Cabecera</span>
              </td>
              <td class="td text-right tabular-nums">{{ fmt(d.colegios) }}</td>
              <td class="td text-right tabular-nums">{{ fmt(d.meta) }}</td>
              <td class="td text-right tabular-nums font-semibold">{{ fmt(d.total) }}</td>
              <td class="td text-center tabular-nums text-[12px]"><b :class="+d.completos === +d.colegios && +d.colegios > 0 ? 'text-fp-700' : ''">{{ fmt(d.completos) }}</b><span class="text-mut"> / {{ fmt(d.colegios) }}</span></td>
              <td class="td text-center tabular-nums text-[12px]"><span class="text-amber-700">{{ fmt(d.parciales) }}</span><span class="text-mut"> + </span><span class="text-red-700">{{ fmt(d.vacios) }}</span></td>
              <td class="td text-right tabular-nums text-red-700 font-semibold">{{ fmt(d.faltan) }}</td>
              <td class="td">
                <div class="flex items-center gap-2">
                  <div class="flex-1 h-1.5 rounded-full bg-fp-50 overflow-hidden"><div class="h-full bar-anim" :class="semColor(d.pct)" :style="{ width: Math.min(d.pct, 100) + '%' }"></div></div>
                  <span class="text-[11px] tabular-nums w-9 text-right">{{ d.pct }}%</span>
                </div>
              </td>
            </tr>
            <tr v-if="!dists.length && !distBusy"><td colspan="8" class="td text-center text-mut py-6">Este municipio no tiene distritos en la estructura JCE.</td></tr>
            <tr v-if="distBusy"><td colspan="8" class="td text-center text-mut py-6">Cargando distritos…</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Municipio: colegios (con lo que falta en cada uno) -->
    <CoberturaColegios v-if="nivel === 'municipio' && sel.mun" :municipio-id="sel.mun" :jce-id="sel.dist" :circ-id="0" :titulo="tituloCob" />
  </section>
</template>
