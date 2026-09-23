<!-- src/components/ModalIdentidad.vue · verificación de identidad contra el padrón en el primer acceso (fase 74) -->
<script setup>
import { ref, computed } from 'vue';
import { showIdent, verificarIdentidad, perfil, logout } from '../stores/auth';
import { cat } from '../stores/catalogo';
import { t } from '../stores/toasts';

const dia = ref(''), mes = ref(0), anio = ref(''), mun = ref(0), busy = ref(false), err = ref('');
const meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
/* Día, mes y año por separado: sin calendario que obligue a recorrer décadas */
const fnac = computed(() => {
  const d = +dia.value, m = +mes.value, a = +anio.value;
  if (!d || !m || !a || a < 1900 || a > 2015 || d < 1 || d > 31) return '';
  const f = new Date(a, m - 1, d);
  if (f.getFullYear() !== a || f.getMonth() !== m - 1 || f.getDate() !== d) return '';   // 31 de febrero, etc.
  return `${a}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
});
const pideMun = computed(() => perfil.value?.identidad_campos === 'fecha_municipio');
const muns = computed(() => [...cat.value].filter(m => m.tipo !== 'OCLEE').sort((a, b) => String(a.nombre).localeCompare(String(b.nombre), 'es')));

const verificar = async () => {
  err.value = '';
  if (!fnac.value) { err.value = 'Escribe una fecha de nacimiento válida: día, mes y año.'; return; }
  busy.value = true;
  const e = await verificarIdentidad(fnac.value, mun.value || null);
  busy.value = false;
  if (e) { err.value = e; return; }
  t('Identidad verificada. ¡Bienvenido(a)!', 'ok');
};
/* Sin los datos a mano: entra solo a consultar; se vuelve a pedir en el próximo ingreso */
const masTarde = () => { showIdent.value = false; t('Podrás consultar. Para registrar, verifica tu identidad en el próximo ingreso.', 'ok'); };
</script>

<template>
  <div v-if="showIdent" class="modal fixed inset-0 z-[75] bg-ink/50 p-4 flex items-center justify-center">
    <div class="card w-full max-w-sm p-5">
      <div class="h-1 w-10 rounded-full bg-fp-600 mb-4"></div>
      <div class="font-serif font-bold text-[18px]">Confirma que eres tú</div>
      <p class="text-[12.5px] text-mut mt-1 mb-4">Hola {{ perfil?.nombre }}. Antes de continuar, verificamos tu identidad con el padrón de la Junta{{ pideMun ? ' con tu fecha de nacimiento y tu municipio' : ' con tu fecha de nacimiento' }}. Tienes tres intentos.</p>
      <div class="space-y-3">
        <div>
          <label class="lbl">Tu fecha de nacimiento</label>
          <div class="grid grid-cols-[4.5rem_1fr_5.5rem] gap-2">
            <input v-model="dia" type="number" inputmode="numeric" min="1" max="31" class="inp text-center" placeholder="Día" autocomplete="off">
            <select v-model.number="mes" class="inp">
              <option :value="0">Mes…</option>
              <option v-for="(n, i) in meses" :key="n" :value="i + 1">{{ n }}</option>
            </select>
            <input v-model="anio" type="number" inputmode="numeric" min="1900" max="2015" class="inp text-center" placeholder="Año" autocomplete="off">
          </div>
          <p class="text-[11px] text-mut mt-1">Ejemplo: 16 · noviembre · 1968, tal como aparece en tu cédula.</p>
        </div>
        <div v-if="pideMun">
          <label class="lbl">Municipio donde votas</label>
          <select v-model.number="mun" class="inp">
            <option :value="0">Elegir…</option>
            <option v-for="m in muns" :key="m.municipio_id" :value="m.municipio_id">{{ m.nombre }}{{ m.provincia_nombre ? ' · ' + m.provincia_nombre : '' }}</option>
          </select>
          <p class="text-[11px] text-mut mt-1">Si votas en el exterior, deja el municipio sin elegir.</p>
        </div>
        <div v-if="err" class="errbx text-[12.5px]">{{ err }}</div>
        <button class="btn-p w-full" :disabled="busy" @click="verificar">{{ busy ? 'Verificando…' : 'Verificar y continuar' }}</button>
        <div class="flex gap-2">
          <button class="btn-o flex-1 text-[12.5px]" :disabled="busy" @click="masTarde">Verificar más tarde · solo consulta</button>
          <button class="btn-o text-[12.5px]" :disabled="busy" @click="logout">Salir</button>
        </div>
        <p class="text-[11px] text-mut leading-snug">Sin verificar no podrás registrar postulantes. Si los datos no coinciden tres veces, el acceso se bloquea y solo la Comisión lo habilita.</p>
      </div>
    </div>
  </div>
</template>
