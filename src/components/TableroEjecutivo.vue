<!-- src/components/TableroEjecutivo.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { RouterLink } from 'vue-router';
import { sb } from '../lib/supabase';
import { fmt } from '../lib/formato';

const props = defineProps({
  kpi:       { type: Object, default: () => ({}) },
  totales:   { type: Object, default: () => ({}) },
  porRegion: { type: Array,  default: () => [] }
});

const n = v => Number(v || 0);

/* ── Control de accesos ── */
const acc = ref({});
onMounted(async () => {
  const { data } = await sb.rpc('portal_control_accesos');
  if (data) acc.value = data;
});
const pctAcceso = computed(() => {
  const d = n(acc.value.designados);
  return d ? Math.round(n(acc.value.con_acceso) * 100 / d) : 0;
});
const barraAcc = computed(() => {
  const d = n(acc.value.designados) || 1;
  return { ok: n(acc.value.con_acceso) * 100 / d, no: n(acc.value.sin_acceso) * 100 / d };
});

/* ── Avance general ── */
const meta = computed(() => n(props.totales.meta) || n(props.kpi.meta));
const reg  = computed(() => n(props.totales.registrados) || n(props.kpi.total));
const pct  = computed(() => meta.value ? Math.min(100, Math.round(reg.value * 100 / meta.value)) : 0);

/* Anillo */
const R = 34, C = 2 * Math.PI * R;
const dash = computed(() => `${(pct.value / 100) * C} ${C}`);

/* ── Cobertura de colegios ── */
const cob = computed(() => {
  const c = n(props.totales.completos), p = n(props.totales.parciales), v = n(props.totales.vacios);
  const t = c + p + v || 1;
  return { c, p, v, t: c + p + v, pc: c * 100 / t, pp: p * 100 / t, pv: v * 100 / t };
});

/* ── Reparto por cargo ── */
const cargos = computed(() => {
  const x = props.kpi.por_cargo || {};
  const objetivo = meta.value / 3;
  return [
    { k: 'Titulares',    v: n(x.delegado_titular),        col: 'bg-fp-600' },
    { k: 'Suplentes',    v: n(x.suplente_delegado),       col: 'bg-fp-400' },
    { k: 'Observadores', v: n(x.observador_escrutinio),   col: 'bg-amber-400' }
  ].map(c => ({ ...c, pct: objetivo ? Math.min(100, Math.round(c.v * 100 / objetivo)) : 0, objetivo }));
});

/* ── Experiencia previa ── */
const exp = computed(() => {
  const t = n(props.kpi.total) || 1;
  const e = n(props.kpi.con_experiencia);
  return { e, nuevos: Math.max(0, n(props.kpi.total) - e), pct: Math.round(e * 100 / t) };
});

/* ── Ritmo ── */
const ritmo = computed(() => {
  const s = n(props.kpi.semana), h = n(props.kpi.hoy);
  const diario = s / 7;
  const falta = Math.max(0, meta.value - reg.value);
  return { hoy: h, semana: s, diario: Math.round(diario), falta,
           dias: diario > 0 ? Math.ceil(falta / diario) : null };
});

const semColor = p => p >= 60 ? 'bg-fp-600' : (p >= 25 ? 'bg-amber-400' : 'bg-red-300');
const semTxt   = p => p >= 60 ? 'text-fp-700' : (p >= 25 ? 'text-amber-700' : 'text-mut');
</script>

<template>
  <div class="grid gap-3 lg:grid-cols-12">

    <!-- Cobertura de colegios · barra apilada -->
    <div class="card p-4 lg:col-span-5">
      <div class="flex items-baseline justify-between gap-2 mb-2.5">
        <span class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut">Cobertura de colegios</span>
        <span class="text-[11.5px] tabular-nums text-mut">{{ fmt(cob.t) }}</span>
      </div>
      <div class="flex h-4 rounded-md overflow-hidden bg-paper" role="img"
           :aria-label="`${cob.c} completos, ${cob.p} incompletos, ${cob.v} sin registro`">
        <div class="bg-fp-600" :style="{ width: cob.pc + '%' }" style="transition:width .7s ease"></div>
        <div class="bg-amber-400" :style="{ width: cob.pp + '%' }" style="transition:width .7s ease"></div>
        <div class="bg-line" :style="{ width: cob.pv + '%' }" style="transition:width .7s ease"></div>
      </div>
      <div class="grid grid-cols-3 gap-2 mt-3">
        <div>
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-sm bg-fp-600 shrink-0"></span>
            <span class="text-[10.5px] text-mut">Completos</span>
          </div>
          <div class="text-[16px] font-bold tabular-nums leading-tight">{{ fmt(cob.c) }}</div>
        </div>
        <div>
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-sm bg-amber-400 shrink-0"></span>
            <span class="text-[10.5px] text-mut">Incompletos</span>
          </div>
          <div class="text-[16px] font-bold tabular-nums leading-tight text-amber-700">{{ fmt(cob.p) }}</div>
        </div>
        <div>
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-sm bg-line shrink-0"></span>
            <span class="text-[10.5px] text-mut">Sin registro</span>
          </div>
          <div class="text-[16px] font-bold tabular-nums leading-tight">{{ fmt(cob.v) }}</div>
        </div>
      </div>
    </div>

    <!-- Reparto por cargo -->
    <div class="card p-4 lg:col-span-4">
      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut mb-2.5">Por cargo</div>
      <div v-for="c in cargos" :key="c.k" class="mb-2.5 last:mb-0">
        <div class="flex items-baseline justify-between gap-2 mb-1">
          <span class="text-[11.5px] truncate">{{ c.k }}</span>
          <span class="text-[11.5px] font-semibold tabular-nums shrink-0">{{ fmt(c.v) }}</span>
        </div>
        <div class="h-1.5 rounded-full bg-paper overflow-hidden">
          <div class="h-full rounded-full" :class="c.col"
               :style="{ width: Math.max(c.pct, c.v ? 2 : 0) + '%', transition: 'width .7s ease' }"></div>
        </div>
      </div>
      <div class="text-[10.5px] text-mut mt-2.5 pt-2 border-t border-line">
        Meta por cargo: {{ fmt(Math.round(cargos[0]?.objetivo || 0)) }}
      </div>
    </div>

    <!-- Experiencia y ritmo -->
    <div class="card p-4 lg:col-span-3 flex flex-col justify-between">
      <div>
        <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut">Con experiencia</div>
        <div class="flex items-baseline gap-1.5 mt-1">
          <span class="text-[24px] font-bold leading-none tabular-nums">{{ exp.pct }}%</span>
          <span class="text-[11px] text-mut">{{ fmt(exp.e) }}</span>
        </div>
        <div class="h-1.5 rounded-full bg-paper overflow-hidden mt-2">
          <div class="h-full rounded-full bg-fp-500" :style="{ width: exp.pct + '%', transition: 'width .7s ease' }"></div>
        </div>
      </div>
      <div class="mt-3 pt-2.5 border-t border-line">
        <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut">Últimos 7 días</div>
        <div class="text-[20px] font-bold leading-none tabular-nums mt-1">{{ fmt(ritmo.semana) }}</div>
        <div class="text-[10.5px] text-mut mt-0.5">{{ fmt(ritmo.diario) }} por día</div>
      </div>
    </div>

    <!-- Acceso al sistema · control administrativo, al final -->
    <div class="card px-4 py-3 lg:col-span-12">
      <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
        <div class="flex items-baseline gap-2 mr-auto">
          <span class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut">Acceso al sistema</span>
          <span class="text-[15px] font-bold tabular-nums">{{ pctAcceso }}%</span>
          <span class="text-[11px] text-mut">de la estructura puede entrar</span>
        </div>

        <div class="flex h-2 w-full sm:w-40 rounded-full overflow-hidden bg-paper order-last sm:order-none" role="img"
             :aria-label="`${acc.con_acceso} con acceso, ${acc.sin_acceso} sin acceso`">
          <div class="bg-fp-600" :style="{ width: barraAcc.ok + '%' }" style="transition:width .7s ease"></div>
          <div class="bg-red-400" :style="{ width: barraAcc.no + '%' }" style="transition:width .7s ease"></div>
        </div>

        <RouterLink to="/dirigencia?v=accesos&c=sin_acceso"
                    class="flex items-center gap-1.5 text-[11.5px] hover:text-fp-700 whitespace-nowrap">
          <span class="w-2 h-2 rounded-sm bg-red-400 shrink-0"></span>
          <span class="text-mut">Sin acceso</span>
          <b class="tabular-nums" :class="n(acc.sin_acceso) ? 'text-red-700' : ''">{{ fmt(acc.sin_acceso) }}</b>
        </RouterLink>

        <RouterLink to="/dirigencia?v=accesos&c=fuera_estructura"
                    class="flex items-center gap-1.5 text-[11.5px] hover:text-fp-700 whitespace-nowrap">
          <span class="w-2 h-2 rounded-sm bg-amber-400 shrink-0"></span>
          <span class="text-mut">Sin designación</span>
          <b class="tabular-nums" :class="n(acc.fuera_estructura) ? 'text-amber-700' : ''">{{ fmt(acc.fuera_estructura) }}</b>
        </RouterLink>

        <RouterLink to="/dirigencia?v=accesos&c=nunca_entraron"
                    class="flex items-center gap-1.5 text-[11.5px] hover:text-fp-700 whitespace-nowrap">
          <span class="text-mut">Nunca ingresaron</span>
          <b class="tabular-nums">{{ fmt(acc.nunca_entraron) }}</b>
        </RouterLink>

        <RouterLink to="/dirigencia?v=accesos"
                    class="text-[11px] font-semibold text-fp-700 hover:underline whitespace-nowrap">Ver detalle ›</RouterLink>
      </div>
    </div>

    <!-- Avance por región · barras compactas -->
    <div v-if="porRegion.length > 1" class="card p-4 lg:col-span-12">
      <div class="text-[10px] font-bold uppercase tracking-[0.14em] text-mut mb-3">Avance por región</div>
      <div class="grid gap-x-6 gap-y-3 sm:grid-cols-2 xl:grid-cols-3">
        <div v-for="r in porRegion" :key="r.region">
          <div class="flex items-baseline justify-between gap-2 mb-1">
            <span class="text-[12.5px] font-semibold truncate">{{ r.region }}</span>
            <span class="text-[11px] text-mut tabular-nums shrink-0">
              {{ fmt(r.total) }} / {{ fmt(r.meta) }}
              <b class="ml-1" :class="semTxt(r.pct)">{{ r.pct }}%</b>
            </span>
          </div>
          <div class="h-2 rounded-full bg-paper overflow-hidden">
            <div class="h-full rounded-full" :class="semColor(r.pct)"
                 :style="{ width: Math.max(Math.min(r.pct, 100), r.total ? 2 : 0) + '%', transition: 'width .7s ease' }"></div>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>
