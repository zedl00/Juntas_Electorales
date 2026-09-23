<!-- src/views/EstructuraView.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { sb } from '../lib/supabase';
import { t } from '../stores/toasts';
import { fmt } from '../lib/formato';
import AnilloAvance from '../components/AnilloAvance.vue';

const nodos = ref([]), cargando = ref(true), err = ref('');
const ruta = ref([]);            // migas: [{ id, nombre }]
const q = ref(''), soloIncompletos = ref(false);

const cargar = async () => {
  cargando.value = true; err.value = '';
  /* Se lee por tramos: Supabase devuelve 1,000 filas por consulta */
  const todos = [];
  let desde = 0; const paso = 1000;
  for (let i = 0; i < 10; i++) {
    const { data, error } = await sb.from('estructura_ejecutiva').select('*')
      .order('orden').order('contexto').order('nombre').range(desde, desde + paso - 1);
    if (error) {
      cargando.value = false;
      err.value = /does not exist|Could not find/i.test(error.message)
        ? 'Falta ejecutar fase39_estructura_rapida.sql en Supabase.'
        : 'No se pudo cargar la estructura: ' + error.message;
      return;
    }
    todos.push(...(data || []));
    if ((data || []).length < paso) break;
    desde += paso;
  }
  nodos.value = todos;
  cargando.value = false;
};
onMounted(cargar);

const refrescando = ref(false);
const refrescar = async () => {
  refrescando.value = true;
  const { data, error } = await sb.rpc('portal_estructura_refrescar');
  refrescando.value = false;
  if (error) { t('No se pudo reconstruir: ' + error.message, 'err'); return; }
  t(`Estructura reconstruida · ${data?.territorios ?? 0} territorios`, 'ok');
  cargar();
};

const padreActual = computed(() => ruta.value.length ? ruta.value[ruta.value.length - 1].id : null);

const visibles = computed(() => {
  let l = nodos.value.filter(n => n.padre === padreActual.value);
  const s = q.value.trim().toLowerCase();
  if (s) l = nodos.value.filter(n => String(n.nombre).toLowerCase().includes(s));
  if (soloIncompletos.value) l = l.filter(n => n.completos < 3);
  return l.sort((a, b) => a.completos - b.completos || String(a.nombre).localeCompare(String(b.nombre)));
});

/* Resumen del nivel que se está viendo, contando también su descendencia */
const descendencia = (id) => {
  const out = [];
  const bajar = (p) => nodos.value.filter(n => n.padre === p).forEach(n => { out.push(n); bajar(n.id); });
  bajar(id);
  return out;
};

const resumen = computed(() => {
  const l = padreActual.value ? descendencia(padreActual.value) : nodos.value;
  const tot = l.length || 1;
  return {
    total: l.length,
    completos: l.filter(n => n.completos === 3).length,
    parciales: l.filter(n => n.completos > 0 && n.completos < 3).length,
    vacios: l.filter(n => n.completos === 0).length,
    pct: Math.round(l.filter(n => n.completos === 3).length * 100 / tot),
    faltaP: l.filter(n => !n.presidente).length,
    faltaS: l.filter(n => !n.secretario).length,
    faltaE: l.filter(n => !n.encargado).length
  };
});

const entrar = (n) => {
  if (!nodos.value.some(x => x.padre === n.id)) return;
  q.value = '';
  ruta.value.push({ id: n.id, nombre: n.nombre });
};
const volverA = (i) => { q.value = ''; ruta.value = ruta.value.slice(0, i + 1); };
const inicio = () => { q.value = ''; ruta.value = []; };

const tieneHijos = (n) => nodos.value.some(x => x.padre === n.id);
const nivelLbl = { provincia: 'Provincia', circ_provincial: 'Circunscripción provincial',
                   municipio: 'Municipio', circ_municipal: 'Circunscripción', distrito: 'Distrito municipal' };
const fmtTel = t2 => { const d = String(t2 || '').replace(/\D/g, ''); return d.length === 10 ? `${d.slice(0,3)}-${d.slice(3,6)}-${d.slice(6)}` : (t2 || ''); };
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <div class="mr-auto">
        <h2 class="font-serif font-bold text-[22px]">Estructura ejecutiva nacional</h2>
        <p class="text-[12.5px] text-mut">Presidente, Secretario General y Encargado Electoral de cada territorio</p>
      </div>
      <button class="btn-o btn-s" :disabled="refrescando" @click="refrescar">
        {{ refrescando ? 'Reconstruyendo…' : '↻ Reconstruir' }}
      </button>
    </div>

    <div v-if="err" class="errbx">{{ err }}</div>

    <!-- Panel de cobertura del nivel actual -->
    <div class="rounded-2xl bg-fp-700 text-white px-5 py-5">
      <div class="flex items-center gap-5">
        <AnilloAvance :pct="resumen.pct" :size="88" :grosor="10" claro />
        <div class="min-w-0">
          <div class="text-[10.5px] font-bold uppercase tracking-[0.16em] text-fp-100/85">
            {{ ruta.length ? ruta[ruta.length - 1].nombre : 'Todo el país' }}
          </div>
          <div class="text-[28px] font-bold leading-none tabular-nums mt-1">
            {{ fmt(resumen.completos) }}<span class="text-[15px] font-normal text-fp-100/85"> de {{ fmt(resumen.total) }}</span>
          </div>
          <div class="text-[12.5px] text-fp-100/85 mt-1">territorios con la dirigencia completa</div>
        </div>
      </div>
      <div class="grid grid-cols-3 gap-2 mt-4">
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Sin Presidente</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(resumen.faltaP) }}</div>
        </div>
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Sin Secretario</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(resumen.faltaS) }}</div>
        </div>
        <div class="rounded-xl bg-white/10 px-3 py-2">
          <div class="text-[10.5px] text-fp-100/85">Sin Encargado</div>
          <div class="text-[17px] font-bold tabular-nums">{{ fmt(resumen.faltaE) }}</div>
        </div>
      </div>
    </div>

    <!-- Migas y filtros -->
    <div class="card p-3 flex flex-wrap items-center gap-2">
      <div class="flex flex-wrap items-center gap-1 text-[13px] mr-auto">
        <button class="font-semibold hover:text-fp-700" :class="ruta.length ? 'text-fp-700' : 'text-ink'" @click="inicio">País</button>
        <template v-for="(r, i) in ruta" :key="r.id">
          <span class="text-mut">›</span>
          <button class="font-semibold hover:text-fp-700" :class="i === ruta.length - 1 ? 'text-ink' : 'text-fp-700'" @click="volverA(i)">{{ r.nombre }}</button>
        </template>
      </div>
      <input v-model="q" class="inp !py-2 text-[13px] max-w-[240px]" placeholder="Buscar territorio…">
      <label class="flex items-center gap-1.5 text-[12.5px] cursor-pointer">
        <input type="checkbox" v-model="soloIncompletos" class="accent-fp-600 w-4 h-4">
        Solo incompletos
      </label>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando la estructura…</div>

    <!-- Cuadrícula de territorios -->
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
      <div v-for="n in visibles" :key="n.id"
           class="card p-4 transition-shadow"
           :class="[tieneHijos(n) ? 'cursor-pointer hover:border-fp-300' : '',
                    n.completos === 3 ? 'border-fp-200' : (n.completos ? 'border-amber-200' : 'border-red-200')]"
           @click="entrar(n)">
        <div class="flex items-start justify-between gap-2 mb-2">
          <div class="min-w-0">
            <div class="font-semibold text-[14px] leading-snug truncate">{{ n.nombre }}</div>
            <div class="text-[11px] text-mut truncate">{{ nivelLbl[n.nivel] }}<span v-if="q && n.contexto"> · {{ n.contexto }}</span></div>
          </div>
          <span class="badge shrink-0"
                :class="n.completos === 3 ? 'border-fp-600 bg-fp-600 text-white'
                      : (n.completos ? 'border-amber-300 bg-amber-50 text-amber-800' : 'border-red-200 bg-red-50 text-red-700')">
            {{ n.completos }} / 3
          </span>
        </div>

        <div class="space-y-1">
          <div class="flex items-center gap-2 text-[11.5px]">
            <span class="w-5 h-5 rounded-md grid place-items-center text-[10px] font-bold shrink-0"
                  :class="n.presidente ? 'bg-fp-600 text-white' : 'bg-red-50 text-red-500 border border-red-200'">P</span>
            <span v-if="n.presidente" class="truncate">{{ n.presidente }}</span>
            <span v-else class="text-red-600 font-semibold">Sin presidente</span>
          </div>
          <div class="flex items-center gap-2 text-[11.5px]">
            <span class="w-5 h-5 rounded-md grid place-items-center text-[10px] font-bold shrink-0"
                  :class="n.secretario ? 'bg-fp-600 text-white' : 'bg-red-50 text-red-500 border border-red-200'">S</span>
            <span v-if="n.secretario" class="truncate">{{ n.secretario }}</span>
            <span v-else class="text-red-600 font-semibold">Sin secretario general</span>
          </div>
          <div class="flex items-center gap-2 text-[11.5px]">
            <span class="w-5 h-5 rounded-md grid place-items-center text-[10px] font-bold shrink-0"
                  :class="n.encargado ? 'bg-fp-600 text-white' : 'bg-red-50 text-red-500 border border-red-200'">E</span>
            <span v-if="n.encargado" class="truncate">{{ n.encargado }}</span>
            <span v-else class="text-red-600 font-semibold">Sin encargado electoral</span>
          </div>
        </div>

        <div v-if="tieneHijos(n)" class="mt-2.5 pt-2 border-t border-line text-[11px] text-fp-700 font-semibold">
          Ver {{ n.hijos || '' }} {{ n.nivel === 'provincia' ? 'municipios' : 'demarcaciones' }} ›
        </div>
      </div>

      <div class="sm:col-span-2 lg:col-span-3 xl:col-span-4 text-[11px] text-mut px-1">
        La estructura se guarda para que la pantalla abra al instante. Pulsa <b>↻ Reconstruir</b> después de crear o modificar dirigencia.
      </div>

      <div v-if="!visibles.length" class="sm:col-span-2 lg:col-span-3 xl:col-span-4 card p-10 text-center text-mut text-[13px]">
        {{ soloIncompletos ? 'No hay territorios incompletos en este nivel.' : 'Sin territorios que mostrar.' }}
      </div>
    </div>
  </section>
</template>
