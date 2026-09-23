<!-- src/views/DirigenciaView.vue -->
<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { sb } from '../lib/supabase';
import { trasladoLbl } from '../lib/constantes';
import { fmt } from '../lib/formato';
import AnilloAvance from '../components/AnilloAvance.vue';

const nodos = ref([]), cargando = ref(true), err = ref('');

/* ── Control de accesos ── */
const route = useRoute(), router = useRouter();
const vista = ref(['accesos','traslados'].includes(route.query.v) ? route.query.v : 'estructura');
const caso = ref(route.query.c || 'sin_acceso');
const detalle = ref([]), detBusy = ref(false), resumen = ref({});
const qAcc = ref('');

/* ── Traslados pendientes de autorización ── */
const trasl = ref([]), traslBusy = ref(false), traslEstado = ref('pendiente');
const cargarTraslados = async () => {
  traslBusy.value = true;
  const { data, error } = await sb.rpc('portal_traslados_pendientes', { p_estado: traslEstado.value });
  traslBusy.value = false;
  if (error) {
    err.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase52_traslados_parametrizables.sql en Supabase.'
      : 'No se pudo cargar: ' + error.message;
    return;
  }
  trasl.value = data || [];
};

const resolver = async (r, aprobar) => {
  const { data, error } = await sb.rpc('portal_traslado_resolver', {
    p_id: r.id, p_aprobar: aprobar, p_nota: null
  });
  if (error) { t('Error: ' + error.message, 'err'); return; }
  if (!data?.ok) { t(data?.msg || 'No se pudo resolver', 'err'); return; }
  t(data.msg, 'ok');
  cargarTraslados();
};

const traslResumen = computed(() => {
  const l = trasl.value;
  const porNivel = {};
  l.forEach(r => { porNivel[r.nivel] = (porNivel[r.nivel] || 0) + 1; });
  return {
    total: l.length,
    pendientes: l.filter(r => r.estado === 'pendiente').length,
    aprobados:  l.filter(r => r.estado === 'aprobado').length,
    rechazados: l.filter(r => r.estado === 'rechazado').length,
    permitidos: l.filter(r => r.estado === 'permitido').length,
    porNivel
  };
});

const nivelCls = n => n === 'otra_provincia' ? 'border-red-300 bg-red-50 text-red-700'
  : 'border-amber-300 bg-amber-50 text-amber-800';

const casos = [
  { k: 'sin_acceso',       t: 'Designados sin acceso',   d: 'Están en la estructura pero no pueden entrar al sistema' },
  { k: 'fuera_estructura', t: 'Acceso sin designación',  d: 'Pueden entrar pero no figuran en el archivo de plenos' },
  { k: 'nunca_entraron',   t: 'Nunca han ingresado',     d: 'Su acceso está creado pero jamás se ha utilizado' }
];

const cargarAccesos = async () => {
  detBusy.value = true;
  const [r, d] = await Promise.all([
    sb.rpc('portal_control_accesos'),
    sb.rpc('portal_accesos_detalle', { p_caso: caso.value })
  ]);
  detBusy.value = false;
  if (r.data) resumen.value = r.data;
  if (d.error) { err.value = 'No se pudo cargar: ' + d.error.message; return; }
  detalle.value = d.data || [];
};

watch(traslEstado, cargarTraslados);
watch([vista, caso], () => {
  if (vista.value === 'traslados') { cargarTraslados(); router.replace({ query: { v: 'traslados' } }); return; }
  if (vista.value === 'accesos') {
    cargarAccesos();
    router.replace({ query: { v: 'accesos', c: caso.value } });
  } else router.replace({ query: {} });
});

const detalleF = computed(() => {
  const q = qAcc.value.trim().toLowerCase();
  if (!q) return detalle.value;
  return detalle.value.filter(r =>
    String(r.nombre).toLowerCase().includes(q) ||
    String(r.territorio || '').toLowerCase().includes(q) ||
    String(r.cedula).includes(q));
});

const rolTxt = { presidente: 'Presidente(a)', secretario_general: 'Secretario(a) General', enc_electoral: 'Encargado(a) Electoral' };
const fmtCedula = c => { const d = String(c||'').replace(/\D/g,''); return d.length === 11 ? `${d.slice(0,3)}-${d.slice(3,10)}-${d.slice(10)}` : c; };

const exportarAcc = () => {
  const h = ['Cédula','Nombre','Cargo','Territorio','Teléfono','Situación'];
  const esc = v => `"${String(v ?? '').replace(/"/g,'""')}"`;
  const csv = [h.map(esc).join(',')].concat(detalleF.value.map(r =>
    [r.cedula, r.nombre, rolTxt[r.rol]||r.rol, r.territorio, r.telefono, r.situacion].map(esc).join(','))).join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['\ufeff'+csv], { type:'text/csv;charset=utf-8' }));
  a.download = `accesos-${caso.value}-${new Date().toISOString().slice(0,10)}.csv`;
  a.click();
};
const ruta = ref([]);
const q = ref(''), soloFaltan = ref(false);

const cargar = async () => {
  cargando.value = true; err.value = '';
  const { data, error } = await sb.rpc('portal_arbol_dirigencia');
  cargando.value = false;
  if (error) {
    err.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase43_arbol_dirigencia.sql en Supabase.'
      : 'No se pudo cargar: ' + error.message;
    return;
  }
  nodos.value = data || [];
};
onMounted(() => { cargar(); if (vista.value === 'accesos') cargarAccesos(); });

const actual = computed(() => ruta.value.length ? ruta.value[ruta.value.length - 1] : null);

const hijos = computed(() => {
  const p = actual.value ? actual.value.id : null;
  let l = nodos.value.filter(n => n.padre === p);
  if (q.value.trim()) {
    const s = q.value.trim().toLowerCase();
    const enPersonas = n => [...(n.presidentes||[]), ...(n.secretarios||[]), ...(n.encargados||[])]
      .some(p => String(p.n || '').toLowerCase().includes(s));
    l = nodos.value.filter(n => String(n.nombre).toLowerCase().includes(s) || enPersonas(n));
  }
  if (soloFaltan.value) l = l.filter(n => n.completos < 3);
  return l.slice().sort((a, b) => a.completos - b.completos || String(a.nombre).localeCompare(String(b.nombre)));
});

/* Cobertura del nivel actual, contando toda su descendencia */
const rama = computed(() => {
  if (!actual.value) return nodos.value;
  const out = [];
  const bajar = p => nodos.value.filter(n => n.padre === p).forEach(n => { out.push(n); bajar(n.id); });
  bajar(actual.value.id);
  return out;
});

const res = computed(() => {
  const l = rama.value, tot = l.length || 1;
  return {
    total: l.length,
    c3: l.filter(n => n.completos === 3).length,
    pct: Math.round(l.filter(n => n.completos === 3).length * 100 / tot),
    fp: l.filter(n => !(n.presidentes||[]).length).length,
    fs: l.filter(n => !(n.secretarios||[]).length).length,
    fe: l.filter(n => !(n.encargados||[]).length).length
  };
});

const abrir = n => { if (n.hijos) { q.value = ''; ruta.value.push(n); } };
const volver = i => { q.value = ''; ruta.value = ruta.value.slice(0, i + 1); };
const inicio = () => { q.value = ''; ruta.value = []; };

const nivelTxt = { provincia: 'Provincia', circ_provincial: 'Circunscripción provincial',
                   municipio: 'Municipio', oclee: 'Oficina OCLEE',
                   circ_municipal: 'Circunscripción', distrito: 'Distrito municipal' };
/* Enlace de WhatsApp con el mensaje ya redactado */
const wa = (tel, quien, territorio, cargo) => {
  const d = String(tel || '').replace(/\D/g, '');
  const num = d.length === 10 ? '1' + d : d;
  const msg = `Saludos ${quien}, le escribe la Secretaría Nacional Electoral de Fuerza del Pueblo ` +
              `en relación con su responsabilidad como ${cargo} de ${territorio}.`;
  return `https://wa.me/${num}?text=${encodeURIComponent(msg)}`;
};

const hijoTxt = n => n.nivel === 'provincia' ? 'municipios'
  : (n.nivel === 'municipio' ? 'demarcaciones' : 'territorios');
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <div class="mr-auto">
        <h2 class="font-serif font-bold text-[22px]">Dirigencia territorial</h2>
        <p class="text-[12.5px] text-mut">Presidente, Secretario General y Encargado Electoral de cada territorio</p>
      </div>
      <button class="btn-o btn-s" @click="cargar">Actualizar</button>
    </div>

    <div v-if="err" class="errbx">{{ err }}</div>

    <!-- Selector de vista -->
    <div class="flex gap-1 p-1 rounded-xl bg-paper w-fit">
      <button class="px-3.5 py-1.5 rounded-lg text-[13px] font-semibold transition-colors"
              :class="vista === 'estructura' ? 'bg-white shadow-sm text-ink' : 'text-mut hover:text-ink'"
              @click="vista = 'estructura'">Estructura</button>
      <button class="px-3.5 py-1.5 rounded-lg text-[13px] font-semibold transition-colors"
              :class="vista === 'accesos' ? 'bg-white shadow-sm text-ink' : 'text-mut hover:text-ink'"
              @click="vista = 'accesos'">Control de accesos</button>
      <button class="px-3.5 py-1.5 rounded-lg text-[13px] font-semibold transition-colors"
              :class="vista === 'traslados' ? 'bg-white shadow-sm text-ink' : 'text-mut hover:text-ink'"
              @click="vista = 'traslados'">Traslados</button>
    </div>

    <!-- ══ Control de accesos ══ -->
    <template v-if="vista === 'accesos'">
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-xl bg-fp-700 text-white px-4 py-3">
          <div class="text-[11px] text-fp-100/85">Designados en la estructura</div>
          <div class="text-[24px] font-bold tabular-nums leading-tight">{{ fmt(resumen.designados || 0) }}</div>
          <div class="text-[11px] text-fp-100/85">{{ fmt(resumen.con_acceso || 0) }} con acceso activo</div>
        </div>
        <button v-for="c in casos" :key="c.k"
                class="rounded-xl px-4 py-3 text-left transition-colors border"
                :class="caso === c.k ? 'bg-white border-fp-400' : 'bg-paper border-transparent hover:border-line'"
                @click="caso = c.k">
          <div class="text-[11px] text-mut">{{ c.t }}</div>
          <div class="text-[24px] font-bold tabular-nums leading-tight"
               :class="c.k === 'sin_acceso' ? 'text-red-700' : (c.k === 'fuera_estructura' ? 'text-amber-700' : 'text-ink')">
            {{ fmt(resumen[c.k] || 0) }}
          </div>
          <div class="text-[10.5px] text-mut leading-snug mt-0.5">{{ c.d }}</div>
        </button>
      </div>

      <div class="card p-3 flex flex-wrap items-center gap-2">
        <span class="text-[13px] font-semibold mr-auto">{{ casos.find(x => x.k === caso)?.t }}</span>
        <input v-model="qAcc" class="inp !py-2 text-[13px] max-w-[240px]" placeholder="Buscar nombre o territorio…">
        <button class="btn-o btn-s" @click="exportarAcc" :disabled="!detalleF.length">⤓ CSV</button>
        <button class="btn-o btn-s" @click="cargarAccesos">Actualizar</button>
      </div>

      <div v-if="detBusy" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

      <div v-else class="card overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full min-w-[820px]">
            <thead class="bg-paper border-b border-line"><tr>
              <th class="th">Nombre</th><th class="th">Cédula</th><th class="th">Cargo</th>
              <th class="th">Territorio</th><th class="th">Teléfono</th><th class="th">Situación</th>
            </tr></thead>
            <tbody>
              <tr v-for="(r, i) in detalleF" :key="i" class="border-b border-line/60">
                <td class="td font-semibold">{{ r.nombre }}</td>
                <td class="td tabular-nums whitespace-nowrap">{{ fmtCedula(r.cedula) }}</td>
                <td class="td text-[12.5px] whitespace-nowrap">{{ rolTxt[r.rol] || r.rol }}</td>
                <td class="td text-[12.5px]">{{ r.territorio }}</td>
                <td class="td text-[12.5px] tabular-nums whitespace-nowrap">{{ r.telefono || '—' }}</td>
                <td class="td text-[11.5px] text-mut">{{ r.situacion }}</td>
              </tr>
              <tr v-if="!detalleF.length">
                <td colspan="6" class="td text-center text-mut py-10">
                  {{ qAcc ? 'Sin coincidencias.' : 'Ninguno en esta situación.' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
          {{ fmt(detalleF.length) }} registros
        </div>
      </div>
    </template>

    <!-- ══ Traslados ══ -->
    <template v-if="vista === 'traslados'">
      <div class="card p-3 flex flex-wrap items-center gap-2">
        <span class="text-[13px] font-semibold mr-auto">Postulantes asignados fuera de su colegio</span>
        <select v-model="traslEstado" class="inp !py-2 text-[13px] max-w-[220px]">
          <option value="pendiente">Pendientes de autorización</option>
          <option value="aprobado">Aprobados</option>
          <option value="rechazado">Rechazados</option>
          <option value="permitido">Permitidos sin trámite</option>
          <option value="todos">Todos</option>
        </select>
        <button class="btn-o btn-s" @click="cargarTraslados">Actualizar</button>
      </div>

      <!-- Conteos -->
      <div class="grid grid-cols-2 lg:grid-cols-5 gap-3">
        <div class="rounded-xl bg-fp-700 text-white px-4 py-3">
          <div class="text-[11px] text-fp-100/85">Traslados</div>
          <div class="text-[26px] font-bold tabular-nums leading-tight">{{ fmt(traslResumen.total) }}</div>
          <div class="text-[10.5px] text-fp-100/85">en el filtro actual</div>
        </div>
        <div class="rounded-xl bg-paper px-4 py-3">
          <div class="text-[11px] text-mut">Pendientes</div>
          <div class="text-[24px] font-bold tabular-nums leading-tight"
               :class="traslResumen.pendientes ? 'text-amber-700' : ''">{{ fmt(traslResumen.pendientes) }}</div>
          <div class="text-[10.5px] text-mut">esperan autorización</div>
        </div>
        <div class="rounded-xl bg-paper px-4 py-3">
          <div class="text-[11px] text-mut">Aprobados</div>
          <div class="text-[24px] font-bold tabular-nums leading-tight text-fp-700">{{ fmt(traslResumen.aprobados) }}</div>
          <div class="text-[10.5px] text-mut">{{ fmt(traslResumen.permitidos) }} sin trámite</div>
        </div>
        <div class="rounded-xl bg-paper px-4 py-3">
          <div class="text-[11px] text-mut">Rechazados</div>
          <div class="text-[24px] font-bold tabular-nums leading-tight"
               :class="traslResumen.rechazados ? 'text-red-700' : ''">{{ fmt(traslResumen.rechazados) }}</div>
        </div>
        <div class="rounded-xl bg-paper px-4 py-3">
          <div class="text-[11px] text-mut mb-1">Por distancia</div>
          <div class="text-[11.5px] space-y-0.5">
            <div v-for="(n, k) in traslResumen.porNivel" :key="k" class="flex justify-between gap-2">
              <span class="truncate text-mut">{{ trasladoLbl[k] || k }}</span>
              <b class="tabular-nums shrink-0">{{ fmt(n) }}</b>
            </div>
            <div v-if="!Object.keys(traslResumen.porNivel).length" class="text-mut">—</div>
          </div>
        </div>
      </div>

      <div v-if="traslBusy" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

      <div v-else class="space-y-2.5">
        <article v-for="r in trasl" :key="r.id" class="card p-4">
          <div class="flex flex-wrap items-start gap-3">
            <div class="min-w-0 mr-auto">
              <div class="font-semibold text-[14px]">{{ r.nombre }}</div>
              <div class="text-[11.5px] text-mut">
                {{ r.numero_formulario }} · {{ rolTxt[r.cargo] || r.cargo }}
                <span v-if="r.telefono"> · {{ r.telefono }}</span>
              </div>
            </div>
            <span class="badge shrink-0" :class="nivelCls(r.nivel)">{{ trasladoLbl[r.nivel] || r.nivel }}</span>
          </div>

          <div class="grid sm:grid-cols-2 gap-2.5 mt-3">
            <div class="rounded-lg bg-paper px-3 py-2">
              <div class="text-[9.5px] font-bold uppercase tracking-wider text-mut">Vota en</div>
              <div class="text-[13px] font-semibold">{{ r.vota_territorio }}</div>
              <div class="text-[11.5px] text-mut">{{ r.vota_colegio || '—' }}</div>
            </div>
            <div class="rounded-lg bg-fp-25 border border-fp-100 px-3 py-2">
              <div class="text-[9.5px] font-bold uppercase tracking-wider text-fp-700">Trabajaría en</div>
              <div class="text-[13px] font-semibold">{{ r.trabaja_territorio }}</div>
              <div class="text-[11.5px] text-mut">Colegio {{ r.trabaja_colegio || '—' }}</div>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-2 mt-3 pt-2.5 border-t border-line">
            <span class="text-[11px] text-mut mr-auto">
              <template v-if="r.estado === 'pendiente'">Registrado por {{ r.registrado_por || '—' }}</template>
              <template v-else>{{ r.estado === 'aprobado' ? 'Aprobado' : (r.estado === 'rechazado' ? 'Rechazado' : 'Permitido') }}
                <span v-if="r.resuelto_por">por {{ r.resuelto_por }}</span></template>
            </span>
            <template v-if="r.estado === 'pendiente'">
              <button class="btn-p btn-s" @click="resolver(r, true)">Aprobar</button>
              <button class="btn-o btn-s" @click="resolver(r, false)">Rechazar</button>
            </template>
          </div>
        </article>

        <div v-if="!trasl.length" class="card p-10 text-center text-mut text-[13px]">
          No hay traslados en esta situación.
        </div>
      </div>
    </template>


    <template v-else>

    <!-- Cobertura del nivel -->
    <div class="rounded-2xl bg-fp-700 text-white px-5 py-5">
      <div class="flex items-center gap-5">
        <AnilloAvance :pct="res.pct" :size="88" :grosor="10" claro />
        <div class="min-w-0">
          <div class="text-[10.5px] font-bold uppercase tracking-[0.16em] text-fp-100/85 truncate">
            {{ actual ? actual.nombre : 'Todo el país' }}
          </div>
          <div class="text-[28px] font-bold leading-none tabular-nums mt-1">
            {{ fmt(res.c3) }}<span class="text-[15px] font-normal text-fp-100/85"> de {{ fmt(res.total) }}</span>
          </div>
          <div class="text-[12.5px] text-fp-100/85 mt-1">territorios con los tres cargos</div>
        </div>
      </div>
      <div class="grid grid-cols-3 gap-2 mt-4">
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Falta Presidente</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(res.fp) }}</div>
        </div>
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Falta Secretario</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(res.fs) }}</div>
        </div>
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Falta Encargado</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(res.fe) }}</div>
        </div>
      </div>
    </div>

    <!-- Migas y filtros -->
    <div class="card p-3 flex flex-wrap items-center gap-2">
      <div class="flex flex-wrap items-center gap-1.5 text-[13px] mr-auto">
        <button class="font-semibold hover:underline" :class="ruta.length ? 'text-fp-700' : 'text-ink'" @click="inicio">País</button>
        <template v-for="(r, i) in ruta" :key="r.id">
          <span class="text-mut">›</span>
          <button class="font-semibold hover:underline" :class="i === ruta.length - 1 ? 'text-ink' : 'text-fp-700'" @click="volver(i)">{{ r.nombre }}</button>
        </template>
      </div>
      <input v-model="q" class="inp !py-2 text-[13px] max-w-[260px]" placeholder="Buscar territorio o persona…">
      <label class="flex items-center gap-1.5 text-[12.5px] cursor-pointer whitespace-nowrap">
        <input type="checkbox" v-model="soloFaltan" class="accent-fp-600 w-4 h-4"> Solo con faltantes
      </label>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

    <div v-else class="grid sm:grid-cols-2 xl:grid-cols-3 gap-3">
      <article v-for="n in hijos" :key="n.id"
               class="card overflow-hidden transition-colors"
               :class="[n.hijos ? 'cursor-pointer hover:border-fp-400' : '',
                        n.completos === 3 ? 'border-fp-200' : (n.completos ? 'border-amber-200' : 'border-red-200')]"
               @click="abrir(n)">
        <header class="px-4 py-3 flex items-start justify-between gap-2"
                :class="n.completos === 3 ? 'bg-fp-25' : (n.completos ? 'bg-amber-50/70' : 'bg-red-50/70')">
          <div class="min-w-0">
            <h3 class="font-semibold text-[14.5px] leading-snug truncate">{{ n.nombre }}</h3>
            <p class="text-[11px] text-mut truncate">{{ nivelTxt[n.nivel] }}<span v-if="q && n.contexto"> · {{ n.contexto }}</span></p>
          </div>
          <span class="badge shrink-0"
                :class="n.completos === 3 ? 'border-fp-600 bg-fp-600 text-white'
                      : (n.completos ? 'border-amber-300 bg-amber-100 text-amber-900' : 'border-red-300 bg-red-100 text-red-800')">
            {{ n.completos }}/3
          </span>
        </header>

        <div class="px-4 py-3 space-y-3">
          <div v-for="c in [
                { l:'Presidente',          ini:'P', gente:n.presidentes },
                { l:'Secretario General',  ini:'S', gente:n.secretarios },
                { l:'Encargado Electoral', ini:'E', gente:n.encargados }]"
               :key="c.ini" class="flex items-start gap-2.5">
            <span class="w-6 h-6 rounded-lg grid place-items-center text-[10px] font-bold shrink-0 mt-0.5"
                  :class="c.gente && c.gente.length ? 'bg-fp-600 text-white' : 'bg-red-50 text-red-400 border border-red-200'">
              {{ c.ini }}
            </span>
            <div class="min-w-0 flex-1">
              <div class="text-[10px] uppercase tracking-wider text-mut">{{ c.l }}</div>

              <template v-if="c.gente && c.gente.length">
                <div v-for="(p, i) in c.gente" :key="i"
                     class="flex items-center gap-1.5 py-0.5"
                     :class="i ? 'border-t border-line/60 mt-0.5 pt-1' : ''">
                  <span class="text-[12.5px] font-medium leading-snug min-w-0 flex-1">
                    <span v-if="p.c" class="badge border-fp-200 bg-fp-50 text-fp-800 mr-1 align-middle">C{{ p.c }}</span>{{ p.n }}
                  </span>
                  <a v-if="p.t" :href="wa(p.t, p.n, n.nombre, c.l)" target="_blank" rel="noopener"
                     class="shrink-0 w-6 h-6 rounded-lg grid place-items-center bg-[#25D366]/12 hover:bg-[#25D366]/30 transition-colors"
                     :title="'Escribir a ' + p.n + ' por WhatsApp'" @click.stop>
                    <svg viewBox="0 0 24 24" class="w-3.5 h-3.5" fill="#128C4B" aria-hidden="true">
                      <path d="M17.5 14.4c-.3-.15-1.8-.9-2.1-1-.28-.1-.48-.15-.68.15s-.78 1-.95 1.2c-.18.2-.35.22-.65.07-.3-.15-1.28-.47-2.43-1.5-.9-.8-1.5-1.8-1.68-2.1-.17-.3-.02-.46.13-.6.14-.14.3-.35.45-.53.15-.18.2-.3.3-.5.1-.2.05-.38-.03-.53-.07-.15-.67-1.63-.92-2.23-.24-.58-.49-.5-.67-.51h-.58c-.2 0-.53.07-.8.38-.28.3-1.05 1.03-1.05 2.5s1.08 2.9 1.23 3.1c.15.2 2.12 3.24 5.14 4.54.72.3 1.28.5 1.71.64.72.23 1.37.2 1.89.12.58-.09 1.8-.74 2.05-1.45.25-.7.25-1.31.18-1.44-.08-.13-.28-.2-.58-.35z"/>
                      <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5.05-1.32A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.18-1.14l-.3-.18-3.1.81.83-3.02-.2-.31A8.2 8.2 0 1 1 12 20.2z"/>
                    </svg>
                  </a>
                </div>
              </template>

              <div v-else class="text-[12.5px] font-semibold text-red-600">Sin asignar</div>
            </div>
          </div>
        </div>

        <footer v-if="n.hijos" class="px-4 py-2.5 border-t border-line text-[11.5px] font-semibold text-fp-700 flex items-center justify-between">
          <span>Ver {{ n.hijos }} {{ hijoTxt(n) }}</span><span>›</span>
        </footer>
      </article>

      <div v-if="!hijos.length" class="sm:col-span-2 xl:col-span-3 card p-10 text-center text-mut text-[13px]">
        {{ soloFaltan ? 'No hay territorios con cargos por cubrir en este nivel.' : 'Sin territorios que mostrar.' }}
      </div>
    </div>
    </template>
  </section>
</template>
