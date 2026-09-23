<!-- src/views/AsignacionView.vue -->
<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { sb } from '../lib/supabase';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';
import { cargoLbl } from '../lib/constantes';
import { perfil, scopeAmplio, esAdmin } from '../stores/auth';
import { cargarSinColegio } from '../stores/kpi';
import { useRouter } from 'vue-router';
import { catMap } from '../stores/catalogo';

const router = useRouter();
const mun = ref(0), cargando = ref(false), err = ref('');
const pendientes = ref([]), colegios = ref([]), resumen = ref({});
const asignados = ref([]), pendAut = ref([]);   // con colegio (para mover) · esperan autorización de la SNE
const infoCol = ref(new Map());                  // id_colegio → { codigo, recinto, distrito, municipio } (fase 70)
const cargarInfoCol = async ids => {
  const faltan = [...new Set(ids.filter(Boolean))].filter(id => !infoCol.value.has(id));
  if (!faltan.length) return;
  const { data } = await sb.rpc('portal_colegio_info', { p_ids: faltan });
  (data || []).forEach(c => infoCol.value.set(c.id_colegio, c));
  infoCol.value = new Map(infoCol.value);
};
const movEleccion = ref({}), moviendo = ref(0), qA = ref(''), soloReub = ref(false);
const irA = (id, reub = null) => {
  if (reub !== null) soloReub.value = reub;
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
};
const territorioDe = r => catMap.value.get(r.municipio_id)?.nombre || ('Municipio ' + r.municipio_id);
const eleccion = ref({});          // id de postulante → colegio elegido
const guardando = ref(0);
const q = ref('');

const munEfectivo = computed(() => scopeAmplio.value ? mun.value : (perfil.value?.municipio_id || 0));

const muns = computed(() => [...catMap.value.values()]
  .sort((a, b) => String(a.nombre).localeCompare(String(b.nombre))));

const cargar = async () => {
  cargando.value = true; err.value = '';
  const id = munEfectivo.value || null;
  const [r, p, c] = await Promise.all([
    sb.rpc('portal_asignacion_resumen', { p_municipio: id }),
    sb.rpc('portal_sin_colegio', { p_municipio: id }),
    id ? sb.rpc('portal_colegios_territorio', { p_municipio: id, p_jce: perfil.value?.jce_id || null })
       : Promise.resolve({ data: [] })
  ]);
  /* Con colegio (para reasignar) y traslados pendientes de la SNE: lectura directa, la RLS acota el alcance */
  const [a, pa] = await Promise.all([
    (() => { let s = sb.from('postulantes_2028')
           .select('id,numero_formulario,nombres,apellido1,apellido2,cargo_postulado,telefono,municipio_id,colegio_asignado,id_colegio_padron,codigo_colegio,traslado_estado')
           .not('colegio_asignado', 'is', null)
           .not('estado', 'in', '("rechazado","no_aprobado")')
           .order('apellido1').range(0, 999);
           return id ? s.eq('municipio_id', id) : s; })(),
    (() => { let s = sb.from('postulantes_2028')
           .select('id,numero_formulario,nombres,apellido1,apellido2,cargo_postulado,municipio_id,colegio_solicitado,colegio_padron_desc,created_at')
           .eq('traslado_estado', 'pendiente').not('estado', 'in', '("rechazado","no_aprobado")')
           .order('created_at').range(0, 999);
           return id ? s.eq('municipio_id', id) : s; })()
  ]);
  cargando.value = false;
  if (p.error) {
    err.value = /does not exist|Could not find/i.test(p.error.message)
      ? 'Falta ejecutar fase56_pendientes_asignacion.sql en Supabase.'
      : 'No se pudo cargar: ' + p.error.message;
    return;
  }
  resumen.value = r.data || {};
  pendientes.value = p.data || [];
  colegios.value = c.data || [];
  asignados.value = a.data || [];
  pendAut.value = pa.data || [];
  cargarInfoCol([...asignados.value.map(x => x.colegio_asignado), ...pendAut.value.map(x => x.colegio_solicitado)]);
  /* Sugerencia: el colegio con más faltantes queda preseleccionado; el encargado solo confirma */
  const sugerido = porRecinto.value[0]?.items?.[0]?.id_colegio;
  if (sugerido) pendientes.value.forEach(x => { if (!eleccion.value[x.id]) eleccion.value[x.id] = sugerido; });
};
onMounted(cargar);
watch(munEfectivo, cargar);

/* Colegios agrupados por recinto, los más vacíos primero */
/* Cada grupo del desplegable dice recinto · distrito · municipio, para saber siempre dónde está el colegio */
const porRecinto = computed(() => {
  const munNom = catMap.value.get(munEfectivo.value)?.nombre || '';
  const g = {};
  colegios.value.forEach(c => {
    const k = [c.recinto, c.distrito && c.distrito !== munNom ? c.distrito : null, munNom].filter(Boolean).join(' · ');
    (g[k] = g[k] || []).push(c);
  });
  return Object.entries(g)
    .map(([recinto, items]) => ({ recinto, items, faltan: items.reduce((a, x) => a + x.faltan, 0) }))
    .sort((a, b) => b.faltan - a.faltan || a.recinto.localeCompare(b.recinto));
});

const conFaltantes = computed(() => colegios.value.filter(c => c.faltan > 0));

const pendVista = computed(() => {
  const s = q.value.trim().toLowerCase();
  if (!s) return pendientes.value;
  return pendientes.value.filter(r =>
    String(r.nombre).toLowerCase().includes(s) || String(r.cedula).includes(s));
});

const asignar = async (row) => {
  const col = eleccion.value[row.id];
  if (!col) { t('Elige primero un colegio', 'err'); return; }
  guardando.value = row.id;
  const { data, error } = await sb.rpc('portal_reasignar_colegio', {
    p_postulante: row.id, p_colegio: col, p_nota: null
  });
  guardando.value = 0;
  if (error) { t('Error: ' + error.message, 'err'); return; }
  if (!data?.ok) { t(data?.msg || 'No se pudo asignar', 'err'); return; }
  t(`${row.nombre} asignado`, 'ok');
  delete eleccion.value[row.id];
  cargar(); cargarSinColegio();
};

/* Mover a alguien que ya tiene colegio a otro colegio del mismo municipio */
const colegioMap = computed(() => new Map(colegios.value.map(c => [c.id_colegio, c])));
const colegioTxt = id => {
  const c = colegioMap.value.get(id);
  if (c) return `${c.codigo} · ${c.recinto}${c.distrito ? ' · ' + c.distrito : ''}`;
  const i = infoCol.value.get(id);
  if (i) return `${i.codigo} · ${i.recinto}${i.distrito && i.distrito !== i.municipio ? ' · ' + i.distrito : ''} · ${i.municipio}`;
  return 'Colegio ' + id;
};
const nombreDe = r => [r.nombres, r.apellido1, r.apellido2].filter(Boolean).join(' ');
const esReubicado = r => r.id_colegio_padron != null && r.colegio_asignado !== r.id_colegio_padron;
const reubicados = computed(() => asignados.value.filter(esReubicado));
const asigVista = computed(() => {
  const s = qA.value.trim().toLowerCase();
  let base = soloReub.value ? reubicados.value : asignados.value;
  if (!s) return base;
  return base.filter(r => nombreDe(r).toLowerCase().includes(s) || colegioTxt(r.colegio_asignado).toLowerCase().includes(s) || territorioDe(r).toLowerCase().includes(s));
});
const colegioAsigTxt = r => colegioTxt(r.colegio_asignado);
const mover = async (row) => {
  const col = movEleccion.value[row.id];
  if (!col || col === row.colegio_asignado) { t('Elige un colegio distinto', 'err'); return; }
  moviendo.value = row.id;
  const { data, error } = await sb.rpc('portal_reasignar_colegio', { p_postulante: row.id, p_colegio: col, p_nota: 'movido desde Asignación' });
  moviendo.value = 0;
  if (error) { t('Error: ' + error.message, 'err'); return; }
  if (!data?.ok) { t(data?.msg || 'No se pudo mover', 'err'); return; }
  t(`${nombreDe(row)} movido a ${colegioTxt(col)}`, 'ok');
  delete movEleccion.value[row.id];
  cargar();
};

const cargoTxt = c => cargoLbl[c] || c;
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <div class="mr-auto">
        <h2 class="font-serif font-bold text-[22px]">Asignación de colegios</h2>
        <p class="text-[12.5px] text-mut">Quién espera colegio y dónde falta gente</p>
      </div>
      <select v-if="scopeAmplio" v-model.number="mun" class="inp !py-2 text-[13px] max-w-[240px]">
        <option :value="0">Todos los municipios</option>
        <option v-for="m in muns" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}</option>
      </select>
      <button class="btn-o btn-s" @click="cargar">Actualizar</button>
    </div>

    <div v-if="err" class="errbx">{{ err }}</div>

    <!-- Resumen: cada tarjeta lleva a su lista -->
    <p class="text-[11.5px] text-mut -mb-1">Toca una tarjeta para ver y trabajar esa lista.</p>
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div class="rounded-xl bg-fp-700 text-white px-4 py-3 cursor-pointer hover:brightness-110" @click="irA('sec-con', false)">
        <div class="text-[11px] text-fp-100/85">Registrados</div>
        <div class="text-[26px] font-bold tabular-nums leading-tight">{{ fmt(resumen.registrados || 0) }}</div>
        <div class="text-[10.5px] text-fp-100/85">en el alcance actual</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3 cursor-pointer hover:bg-fp-25" @click="irA('sec-con', false)">
        <div class="text-[11px] text-mut">Con colegio</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight text-fp-700">{{ fmt(resumen.con_colegio || 0) }}</div>
        <div class="text-[10.5px] text-mut">cubren una mesa concreta</div>
      </div>
      <div class="rounded-xl px-4 py-3 cursor-pointer hover:bg-amber-100/60" :class="resumen.sin_colegio ? 'bg-amber-50 border border-amber-200' : 'bg-paper'" @click="irA('sec-esperan')">
        <div class="text-[11px] text-mut">Sin colegio</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight" :class="resumen.sin_colegio ? 'text-amber-700' : ''">
          {{ fmt(resumen.sin_colegio || 0) }}
        </div>
        <div class="text-[10.5px] text-mut">esperan asignación</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3 cursor-pointer hover:bg-fp-25" @click="irA('sec-con', true)">
        <div class="text-[11px] text-mut">Reubicados</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight">{{ fmt(resumen.reubicados || 0) }}</div>
        <div class="text-[10.5px] text-mut">trabajan fuera de su colegio</div>
      </div>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

    <template v-else>
      <!-- Pendientes de asignar -->
      <div id="sec-esperan" class="card p-4 scroll-mt-20">
        <div class="flex flex-wrap items-baseline gap-2 mb-3">
          <h3 class="font-serif font-bold text-[16px] mr-auto">Esperan colegio · {{ fmt(pendVista.length) }}</h3>
          <input v-model="q" class="inp !py-1.5 text-[12.5px] max-w-[200px]" placeholder="Buscar…">
        </div>

        <!-- Vista nacional: se listan todos los que esperan, con acceso directo a su municipio -->
        <div v-if="!munEfectivo && scopeAmplio && pendVista.length" class="space-y-2">
          <p class="text-[12px] text-mut">Para asignar hay que entrar al municipio de cada persona. Pulsa el botón y el desplegable cambia solo.</p>
          <div v-for="r in pendVista" :key="r.id"
               class="rounded-xl border border-amber-200 bg-amber-50/40 p-3 flex flex-wrap items-center gap-3">
            <div class="min-w-0 mr-auto">
              <div class="font-semibold text-[13.5px]">{{ r.nombre }}</div>
              <div class="text-[11.5px] text-mut">{{ r.numero_formulario }} · {{ cargoTxt(r.cargo) }} · registrado en <b>{{ r.territorio }}</b></div>
              <div class="text-[11.5px] text-mut mt-0.5">Vota en <b>{{ r.vota_municipio }}</b> · {{ r.vota_colegio }}</div>
            </div>
            <button class="btn-p btn-s" @click="mun = r.municipio_id">Asignar en {{ r.territorio }} →</button>
          </div>
        </div>

        <div v-else-if="!pendVista.length" class="text-[13px] text-mut py-6 text-center">
          {{ q ? 'Sin coincidencias.' : 'Todos los postulantes tienen colegio asignado.' }}
        </div>

        <div v-else class="space-y-2.5">
          <div v-for="r in pendVista" :key="r.id"
               class="rounded-xl border border-amber-200 bg-amber-50/40 p-3">
            <div class="flex flex-wrap items-start gap-3">
              <div class="min-w-0 mr-auto">
                <div class="font-semibold text-[13.5px]">{{ r.nombre }}</div>
                <div class="text-[11.5px] text-mut">
                  {{ r.numero_formulario }} · {{ cargoTxt(r.cargo) }}
                  <span v-if="r.telefono"> · {{ r.telefono }}</span>
                </div>
                <div class="text-[11.5px] text-mut mt-0.5">
                  Vota en <b>{{ r.vota_municipio }}</b> · {{ r.vota_colegio }}
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <select v-model.number="eleccion[r.id]" class="inp !py-1.5 text-[12.5px] max-w-[280px]" title="Viene preseleccionado el colegio con más faltantes">
                  <option :value="undefined">Elegir colegio…</option>
                  <optgroup v-for="g in porRecinto" :key="g.recinto" :label="g.recinto">
                    <option v-for="c in g.items" :key="c.id_colegio" :value="c.id_colegio">
                      {{ c.codigo }} — {{ c.personas }} de 3{{ c.faltan ? ' · faltan ' + c.faltan : ' · completo' }}
                    </option>
                  </optgroup>
                </select>
                <button class="btn-p btn-s" :disabled="guardando === r.id || !eleccion[r.id]" @click="asignar(r)">
                  {{ guardando === r.id ? 'Asignando…' : 'Asignar' }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Esperan autorización de la SNE: no cuentan hasta que se apruebe el traslado -->
      <div v-if="pendAut.length" class="card p-4 border-amber-300">
        <div class="flex flex-wrap items-baseline gap-2 mb-1">
          <h3 class="font-serif font-bold text-[16px] mr-auto">Esperan autorización de la SNE · {{ fmt(pendAut.length) }}</h3>
          <button v-if="esAdmin" class="btn-o btn-s" @click="router.push({ path: '/dirigencia', query: { v: 'traslados' } })">Ir a la bandeja de traslados →</button>
        </div>
        <p class="text-[12px] text-mut mb-3">Su traslado excede el alcance configurado. Tienen colegio solicitado, pero no cuentan para la cobertura hasta que la SNE apruebe.</p>
        <div v-for="r in pendAut" :key="r.id" class="text-[12.5px] py-1.5 border-b border-line/60 last:border-0 flex flex-wrap gap-x-3">
          <b>{{ nombreDe(r) }}</b>
          <span class="text-mut">{{ r.numero_formulario }} · {{ cargoTxt(r.cargo_postulado) }}</span>
          <span class="text-mut">vota en {{ r.colegio_padron_desc || '—' }}</span>
          <span v-if="r.colegio_solicitado" class="badge border-amber-300 bg-amber-50 text-amber-800">solicita {{ colegioTxt(r.colegio_solicitado) }}</span>
        </div>
      </div>

      <!-- Con colegio: mover entre colegios del mismo municipio -->
      <div id="sec-con" class="card p-4 scroll-mt-20">
        <div class="flex flex-wrap items-center gap-2 mb-3">
          <h3 class="font-serif font-bold text-[16px] mr-auto">{{ soloReub ? 'Reubicados' : 'Con colegio' }} · {{ fmt(asigVista.length) }}</h3>
          <label class="flex items-center gap-1.5 text-[12px] cursor-pointer"><input type="checkbox" v-model="soloReub" class="accent-fp-600"> Solo reubicados</label>
          <input v-model="qA" class="inp !py-1.5 text-[12.5px] max-w-[200px]" placeholder="Buscar…">
        </div>
        <p class="text-[12px] text-mut mb-3">
          {{ soloReub ? 'Trabajan en un colegio distinto del que les toca por el padrón.' : 'Para mover a alguien a otro colegio del mismo municipio. Queda constancia en la bitácora.' }}
          <span v-if="!munEfectivo"> Para mover, entra al municipio con el botón de cada fila.</span>
        </p>
        <div v-if="!asigVista.length" class="text-[13px] text-mut py-4 text-center">{{ qA ? 'Sin coincidencias.' : (soloReub ? 'Nadie está reubicado.' : 'Nadie tiene colegio asignado todavía.') }}</div>
        <div v-else class="space-y-2">
          <div v-for="r in asigVista" :key="r.id" class="rounded-xl border border-line p-3 flex flex-wrap items-center gap-3">
            <div class="min-w-0 mr-auto">
              <div class="font-semibold text-[13.5px]">{{ nombreDe(r) }} <span v-if="esReubicado(r)" class="badge border-sky-200 bg-sky-50 text-sky-800 ml-1">reubicado</span></div>
              <div class="text-[11.5px] text-mut">{{ r.numero_formulario }} · {{ cargoTxt(r.cargo_postulado) }}<span v-if="!munEfectivo"> · {{ territorioDe(r) }}</span> · en <b>{{ colegioAsigTxt(r) }}</b><span v-if="esReubicado(r) && r.codigo_colegio" class="text-mut"> · vota en {{ r.codigo_colegio }}</span></div>
            </div>
            <button v-if="!munEfectivo" class="btn-o btn-s" @click="mun = r.municipio_id">Entrar a {{ territorioDe(r) }} →</button>
            <div v-else class="flex flex-wrap items-center gap-2">
              <select v-model.number="movEleccion[r.id]" class="inp !py-1.5 text-[12.5px] max-w-[280px]">
                <option :value="undefined">Mover a…</option>
                <optgroup v-for="g in porRecinto" :key="g.recinto" :label="g.recinto">
                  <option v-for="c in g.items" :key="c.id_colegio" :value="c.id_colegio" :disabled="c.id_colegio === r.colegio_asignado">
                    {{ c.codigo }} — {{ c.personas }} de 3{{ c.faltan ? ' · faltan ' + c.faltan : ' · completo' }}
                  </option>
                </optgroup>
              </select>
              <button class="btn-o btn-s" :disabled="moviendo === r.id || !movEleccion[r.id]" @click="mover(r)">{{ moviendo === r.id ? 'Moviendo…' : 'Mover' }}</button>
            </div>
          </div>
          <p v-if="asignados.length >= 1000" class="text-[11px] text-mut">Se muestran los primeros 1,000.</p>
        </div>
      </div>

      <!-- Colegios con faltantes -->
      <div v-if="munEfectivo" class="card p-4">
        <h3 class="font-serif font-bold text-[16px] mb-1">Colegios con faltantes · {{ fmt(conFaltantes.length) }}</h3>
        <p class="text-[12px] text-mut mb-3">Ordenados por los que más gente necesitan.</p>

        <div v-if="!conFaltantes.length" class="text-[13px] text-mut py-6 text-center">
          Todos los colegios de este territorio están completos.
        </div>

        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[560px]">
            <thead class="bg-paper border-b border-line"><tr>
              <th class="th">Colegio</th><th class="th">Recinto</th>
              <th class="th text-center">Electores</th><th class="th text-center">Personas</th>
              <th class="th text-center">Faltan</th>
            </tr></thead>
            <tbody>
              <tr v-for="c in conFaltantes.slice(0, 60)" :key="c.id_colegio" class="border-b border-line/60">
                <td class="td font-semibold tabular-nums">{{ c.codigo }}</td>
                <td class="td text-[12.5px]">{{ c.recinto }}</td>
                <td class="td text-center text-[12.5px] tabular-nums">{{ fmt(c.inscritos) }}</td>
                <td class="td text-center text-[12.5px] tabular-nums">{{ c.personas }} de 3</td>
                <td class="td text-center">
                  <span class="badge" :class="c.faltan === 3 ? 'border-red-200 bg-red-50 text-red-700' : 'border-amber-300 bg-amber-50 text-amber-800'">
                    {{ c.faltan }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <p v-if="conFaltantes.length > 60" class="text-[11px] text-mut mt-2">
            Se muestran los 60 con más faltantes de {{ fmt(conFaltantes.length) }}.
          </p>
        </div>
      </div>
    </template>
  </section>
</template>
