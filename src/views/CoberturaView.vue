<!-- src/views/CoberturaView.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { sb } from '../lib/supabase';
import { fmt } from '../lib/formato';
import { t } from '../stores/toasts';

const filas = ref([]), cargando = ref(true), err = ref('');
const f = ref({ q: '', nivel: '', prov: '', estado: '' });

const cargar = async () => {
  cargando.value = true; err.value = '';
  const { data, error } = await sb.rpc('portal_cobertura_dirigencia');
  cargando.value = false;
  if (error) {
    err.value = /does not exist|Could not find/i.test(error.message)
      ? 'Falta ejecutar fase42_cobertura_simple.sql en Supabase.'
      : 'No se pudo cargar: ' + error.message;
    return;
  }
  filas.value = data || [];
};
onMounted(cargar);

const provincias = computed(() =>
  [...new Set(filas.value.map(r => r.provincia).filter(Boolean))].sort());

const vista = computed(() => {
  const q = f.value.q.trim().toLowerCase();
  return filas.value.filter(r => {
    if (q && !String(r.territorio).toLowerCase().includes(q)
          && !String(r.presidente || '').toLowerCase().includes(q)
          && !String(r.secretario || '').toLowerCase().includes(q)
          && !String(r.encargado || '').toLowerCase().includes(q)) return false;
    if (f.value.nivel && r.nivel !== f.value.nivel) return false;
    if (f.value.prov && r.provincia !== f.value.prov) return false;
    if (f.value.estado === 'completo'   && r.completos !== 3) return false;
    if (f.value.estado === 'incompleto' && (r.completos === 3 || r.completos === 0)) return false;
    if (f.value.estado === 'vacio'      && r.completos !== 0) return false;
    return true;
  });
});

const res = computed(() => {
  const l = vista.value;
  return {
    total: l.length,
    c3: l.filter(r => r.completos === 3).length,
    c12: l.filter(r => r.completos > 0 && r.completos < 3).length,
    c0: l.filter(r => r.completos === 0).length,
    fp: l.filter(r => !r.presidente).length,
    fs: l.filter(r => !r.secretario).length,
    fe: l.filter(r => !r.encargado).length
  };
});

const limpiar = () => { f.value = { q: '', nivel: '', prov: '', estado: '' }; };

const exportar = () => {
  sb.rpc('portal_log_exportacion', { p_tipo: 'cobertura_dirigencia_csv', p_registros: vista.value.length }).then(() => {}, () => {});
  const h = ['Nivel','Provincia','Territorio','Presidente','Secretario General','Encargado Electoral','Cargos'];
  const esc = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = [h.map(esc).join(',')]
    .concat(vista.value.map(r => [r.nivel, r.provincia, r.territorio,
      r.presidente || 'FALTA', r.secretario || 'FALTA', r.encargado || 'FALTA',
      r.completos + ' de 3'].map(esc).join(',')))
    .join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `cobertura-dirigencia-${new Date().toISOString().slice(0,10)}.csv`;
  a.click();
  t('Archivo descargado', 'ok');
};
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <div class="mr-auto">
        <h2 class="font-serif font-bold text-[22px]">Cobertura de dirigencia</h2>
        <p class="text-[12.5px] text-mut">Presidente, Secretario General y Encargado Electoral por territorio</p>
      </div>
      <button class="btn-o btn-s" @click="exportar">⤓ Descargar CSV</button>
      <button class="btn-o btn-s" @click="cargar">Actualizar</button>
    </div>

    <div v-if="err" class="errbx">{{ err }}</div>

    <!-- Indicadores -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div class="rounded-xl bg-fp-700 text-white px-4 py-3">
        <div class="text-[11px] text-fp-100/85">Con los 3 cargos</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight">{{ fmt(res.c3) }}
          <span class="text-[13px] font-normal text-fp-100/85">de {{ fmt(res.total) }}</span></div>
        <div class="h-1.5 rounded-full bg-white/20 overflow-hidden mt-2">
          <div class="h-full bg-fp-100" :style="{ width: (res.total ? res.c3*100/res.total : 0) + '%' }"></div>
        </div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Incompletos</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight text-amber-700">{{ fmt(res.c12) }}</div>
        <div class="text-[11px] text-mut">falta uno o dos cargos</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut">Sin dirigencia</div>
        <div class="text-[24px] font-bold tabular-nums leading-tight text-red-600">{{ fmt(res.c0) }}</div>
        <div class="text-[11px] text-mut">ningún cargo asignado</div>
      </div>
      <div class="rounded-xl bg-paper px-4 py-3">
        <div class="text-[11px] text-mut mb-1">Cargos por cubrir</div>
        <div class="text-[12px] space-y-0.5">
          <div class="flex justify-between"><span>Presidente</span><b class="tabular-nums">{{ fmt(res.fp) }}</b></div>
          <div class="flex justify-between"><span>Secretario</span><b class="tabular-nums">{{ fmt(res.fs) }}</b></div>
          <div class="flex justify-between"><span>Encargado</span><b class="tabular-nums">{{ fmt(res.fe) }}</b></div>
        </div>
      </div>
    </div>

    <!-- Filtros -->
    <div class="card p-3 grid sm:grid-cols-2 lg:grid-cols-5 gap-2">
      <input v-model="f.q" class="inp !py-2 text-[13px]" placeholder="Buscar territorio o persona…">
      <select v-model="f.nivel" class="inp !py-2 text-[13px]">
        <option value="">Nivel: todos</option>
        <option value="Provincia">Provincia</option>
        <option value="Municipio">Municipio</option>
        <option value="Distrito">Distrito municipal</option>
        <option value="OCLEE">OCLEE</option>
      </select>
      <select v-model="f.prov" class="inp !py-2 text-[13px]">
        <option value="">Provincia: todas</option>
        <option v-for="p in provincias" :key="p" :value="p">{{ p }}</option>
      </select>
      <select v-model="f.estado" class="inp !py-2 text-[13px]">
        <option value="">Estado: todos</option>
        <option value="completo">Completos</option>
        <option value="incompleto">Incompletos</option>
        <option value="vacio">Sin dirigencia</option>
      </select>
      <button class="btn-o !py-2" @click="limpiar">Limpiar</button>
    </div>

    <div v-if="cargando" class="card p-10 text-center text-mut text-[13px]">Cargando…</div>

    <div v-else class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[900px]">
          <thead class="bg-paper border-b border-line"><tr>
            <th class="th">Territorio</th><th class="th">Nivel</th>
            <th class="th">Presidente</th><th class="th">Secretario General</th>
            <th class="th">Encargado Electoral</th><th class="th text-center">Cargos</th>
          </tr></thead>
          <tbody>
            <tr v-for="(r, i) in vista" :key="i" class="border-b border-line/60"
                :class="r.completos === 0 ? 'bg-red-50/40' : (r.completos < 3 ? 'bg-amber-50/40' : '')">
              <td class="td">
                <div class="font-semibold text-[13px]">{{ r.territorio }}</div>
                <div class="text-[11px] text-mut">{{ r.provincia }}</div>
              </td>
              <td class="td text-[12px] text-mut whitespace-nowrap">{{ r.nivel }}</td>
              <td class="td text-[12.5px]">
                <span v-if="r.presidente">{{ r.presidente }}</span>
                <span v-else class="text-red-600 font-semibold">FALTA</span>
              </td>
              <td class="td text-[12.5px]">
                <span v-if="r.secretario">{{ r.secretario }}</span>
                <span v-else class="text-red-600 font-semibold">FALTA</span>
              </td>
              <td class="td text-[12.5px]">
                <span v-if="r.encargado">{{ r.encargado }}</span>
                <span v-else class="text-red-600 font-semibold">FALTA</span>
              </td>
              <td class="td text-center whitespace-nowrap">
                <span class="badge" :class="r.completos === 3 ? 'border-fp-600 bg-fp-600 text-white'
                  : (r.completos ? 'border-amber-300 bg-amber-50 text-amber-800' : 'border-red-200 bg-red-50 text-red-700')">
                  {{ r.completos }} / 3
                </span>
              </td>
            </tr>
            <tr v-if="!vista.length"><td colspan="6" class="td text-center text-mut py-10">Sin territorios que coincidan con el filtro.</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">
        {{ fmt(vista.length) }} territorios · los que están sin dirigencia aparecen sobre fondo rojo, los incompletos en ámbar
      </div>
    </div>
  </section>
</template>
