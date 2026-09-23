/* src/stores/catalogo.js */
import { ref, computed } from 'vue';
import { sb } from '../lib/supabase';
import { t } from './toasts';
import { perfil } from './auth';

/* Catálogo de territorios: vista portal_metas_municipio (inmune a políticas RLS externas) */

export const cat = ref([]);
export const catMap = computed(() => new Map(cat.value.map(m => [m.municipio_id, m])));

export const catScope = computed(() => {
  const p = perfil.value; if (!p) return [];
  if (p.rol === 'admin_sne') return cat.value;
  if (p.rol === 'coordinador_regional') return cat.value.filter(m => m.macroregion === p.region);
  if (p.rol === 'supervisor_provincial') return cat.value.filter(m => m.provincia_id === p.provincia_id);
  return cat.value.filter(m => m.municipio_id === p.municipio_id);
});

export const regiones = computed(() => [...new Set(catScope.value.map(m => m.macroregion).filter(Boolean))].sort());

export const provsOf = region =>
  [...new Map(catScope.value
      .filter(m => m.provincia_tipo !== 'OCLEE' && m.provincia_id && m.provincia_nombre
                && (!region || m.macroregion === region))
      .map(m => [m.provincia_id, { id: m.provincia_id, nombre: m.provincia_nombre }])).values()]
    .sort((a, b) => String(a.nombre).localeCompare(String(b.nombre)));

export const munsOf = (region, prov) =>
  catScope.value
    .filter(m => (!region || m.macroregion === region) && (!prov || m.provincia_id === prov))
    .sort((a, b) => String(a.nombre).localeCompare(b.nombre));

export const catGrupos = computed(() => {
  const g = {};
  catScope.value.forEach(m => { const k = m.provincia_nombre || '—'; (g[k] = g[k] || []).push(m); });
  return Object.keys(g).sort().map(k => ({ prov: k, items: g[k].sort((a, b) => String(a.nombre).localeCompare(b.nombre)) }));
});


/* Jerarquía territorial para los filtros encadenados
   Ámbito → Región → Provincia → Municipio → Distrito Municipal */
const enAmbito = (m, ambito) =>
  !ambito || (ambito === 'oclee' ? m.tipo === 'OCLEE' : m.tipo !== 'OCLEE');

/** Municipios "padre" (no-DM) del alcance, filtrados por ámbito/región/provincia. */
export const munPadres = (ambito, region, prov) =>
  catScope.value
    .filter(m => enAmbito(m, ambito)
              && (!region || m.macroregion === region)
              && (!prov || m.provincia_id === prov))
    .sort((a, b) => String(a.nombre).localeCompare(b.nombre));

/** Distritos Municipales hijos de un municipio. */
export const hijosDe = id =>
  catScope.value
    .filter(m => m.municipio_padre_id === id)
    .sort((a, b) => String(a.nombre).localeCompare(b.nombre));

export const nombreMun = id => catMap.value.get(id)?.nombre || (perfil.value?.municipio_id === id ? perfil.value.municipio : '—');

export async function cargarCat() {
  /* Supabase devuelve 1,000 filas por consulta: se pide por tramos */
  const todos = [];
  let desde = 0; const paso = 1000;
  for (let i = 0; i < 10; i++) {
    const { data, error } = await sb.from('portal_metas_municipio').select('*')
      .order('nombre').range(desde, desde + paso - 1);
    if (error) { t('No se pudo cargar el catálogo de territorios', 'err'); return; }
    todos.push(...(data || []));
    if ((data || []).length < paso) break;
    desde += paso;
  }
  cat.value = todos.filter(m => m.estatus !== 'I');
}
