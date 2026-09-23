import { ref, reactive, computed } from 'vue';
import { sb } from '../lib/supabase';
import { cargoLbl, estadoOrden } from '../lib/constantes';
import { scopeAmplio } from './auth';

/* ── KPI del alcance del usuario ── */
export const kpi = ref(null);
export const kpiBusy = ref(false);

export const avancePct = computed(() => {
  const k = kpi.value; if (!k || !Number(k.meta)) return 0;
  return Math.round(Number(k.total || 0) / Number(k.meta) * 100);
});

export const semColor = p => p >= 60 ? 'bg-fp-600' : (p >= 25 ? 'bg-amber-400' : 'bg-red-400');

export const estadoBars = computed(() => {
  const pe = kpi.value?.por_estado || {}; const tot = Number(kpi.value?.total || 0) || 1;
  return estadoOrden.filter(k => pe[k]).map(k => ({ k, n: pe[k], pct: Math.round(pe[k] / tot * 100) }));
});

export const cargoBars = computed(() => {
  const pc = kpi.value?.por_cargo || {}; const tot = Number(kpi.value?.total || 0) || 1;
  return Object.keys(cargoLbl).filter(k => pc[k]).map(k => ({ k, n: pc[k], pct: Math.round(pc[k] / tot * 100) }));
});

export async function cargarKpi() {
  kpiBusy.value = true;
  const { data, error } = await sb.rpc('portal_kpi', { p_municipio: null });
  if (!error) kpi.value = data;
  kpiBusy.value = false;
}

/* ── Avance por territorio (roles con alcance amplio) ── */
export const terr = ref([]);
export const terrBusy = ref(false);
export const terrFRegion = ref(''), terrFProv = ref(''), terrFQ = ref(''), terrSinAct = ref(false);
export const terrSort = reactive({ c: 'total', asc: false });

export const terrOrden = c => {
  if (terrSort.c === c) terrSort.asc = !terrSort.asc;
  else { terrSort.c = c; terrSort.asc = (c === 'municipio' || c === 'provincia'); }
};
export const tArrow = c => terrSort.c === c ? (terrSort.asc ? '▲' : '▼') : '';

export async function cargarTerr() {
  if (!scopeAmplio.value) return;
  terrBusy.value = true;
  const { data, error } = await sb.rpc('portal_kpi_territorios');
  if (!error) terr.value = (data || []).map(r => ({
    ...r,
    total: Number(r.total || 0),
    meta: Number(r.meta || 0),
    pct: Number(r.meta) ? Math.round(Number(r.total || 0) / Number(r.meta) * 100) : 0
  }));
  terrBusy.value = false;
}

const terrBase = computed(() => terr.value.filter(r =>
  (!terrFRegion.value || r.macroregion === terrFRegion.value) &&
  (!terrFProv.value || r.provincia_id === terrFProv.value) &&
  (!terrFQ.value || String(r.municipio || '').toLowerCase().includes(terrFQ.value.toLowerCase()))
));

export const terrSinCuenta = computed(() => terrBase.value.filter(r => !r.total).length);

export const terrView = computed(() => {
  let l = terrSinAct.value ? terrBase.value.filter(r => !r.total) : terrBase.value.slice();
  const { c, asc } = terrSort;
  l.sort((a, b) => {
    const va = a[c], vb = b[c];
    const r = (typeof va === 'string') ? String(va || '').localeCompare(String(vb || '')) : (Number(va || 0) - Number(vb || 0));
    return asc ? r : -r;
  });
  return l;
});

/* ── Cobertura por colegio electoral (resumen por territorio) ── */
export const cob = ref(new Map());   // municipio_id → { colegios, completos, parciales, vacios }

export async function cargarCobertura() {
  if (!scopeAmplio.value) return;
  const { data, error } = await sb.rpc('portal_cobertura_resumen');
  if (!error) cob.value = new Map((data || []).map(r => [r.municipio_id, r]));
}

export function refrescar() { cargarKpi(); cargarTerr(); cargarCobertura(); }
