<!-- src/views/AsignacionView.vue -->
<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { sb } from '../lib/supabase';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';
import { cargoLbl } from '../lib/constantes';
import { perfil, scopeAmplio } from '../stores/auth';
import { catMap } from '../stores/catalogo';

const mun = ref(0), cargando = ref(false), err = ref('');
const pendientes = ref([]), colegios = ref([]), resumen = ref({});
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
};
onMounted(cargar);
watch(munEfectivo, cargar);

/* Colegios agrupados por recinto, los más vacíos primero */
const porRecinto = computed(() => {
  const g = {};
  colegios.value.forEach(c => { (g[c.recinto] = g[c.recinto] || []).push(c); });
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

    <!-- Resumen -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div class="rounded-xl bg-fp-700 text-white px-4 py-3">
        <div class="text-[11px] text-fp-100/85">Registrados</div>
        <div class="text-[26px] font-bold tabular-nums leading-tight">{{ fmt(resumen.registrados || 0) }}</div>
        <div class="text-[10.5px] text-fp-100/85">en el alcance actual</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Con colegio</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight text-fp-700">{{ fmt(resumen.con_colegio || 0) }}</div>
        <div class="text-[10.5px] text-mut">cubren una mesa concreta</div>
      </div>
      <div class="rounded-xl px-4 py-3" :class="resumen.sin_colegio ? 'bg-amber-50 border border-amber-200' : 'bg-paper'">
        <div class="text-[11px] text-mut">Sin colegio</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight" :class="resumen.sin_colegio ? 'text-amber-700' : ''">
          {{ fmt(resumen.sin_colegio || 0) }}
        </div>
        <div class="text-[10.5px] text-mut">esperan asignación</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Reubicados</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight">{{ fmt(resumen.reubicados || 0) }}</div>
        <div class="text-[10.5px] text-mut">trabajan fuera de su colegio</div>
      </div>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

    <template v-else>
      <!-- Pendientes de asignar -->
      <div class="card p-4">
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
                <select v-model.number="eleccion[r.id]" class="inp !py-1.5 text-[12.5px] max-w-[280px]">
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
