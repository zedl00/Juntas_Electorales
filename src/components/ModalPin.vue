<script setup>
import { ref } from 'vue';
import { showPin, showIdent, guardarPin } from '../stores/auth';
import { t } from '../stores/toasts';

const np1 = ref(''), np2 = ref(''), pinBusy = ref(false), pinErr = ref('');

const guardar = async () => {
  pinErr.value = '';
  if (String(np1.value).length < 6) { pinErr.value = 'El PIN debe tener al menos 6 caracteres.'; return; }
  if (np1.value !== np2.value) { pinErr.value = 'Los PIN no coinciden.'; return; }
  pinBusy.value = true;
  const err = await guardarPin(np1.value);
  pinBusy.value = false;
  if (err) { pinErr.value = err; return; }
  np1.value = ''; np2.value = '';
  t('PIN personal creado. ¡Bienvenido(a)!', 'ok');
};
</script>

<template>
  <div v-if="showPin && !showIdent" class="modal fixed inset-0 z-[70] bg-ink/50 p-4 flex items-center justify-center">
    <div class="card w-full max-w-sm p-5">
      <div class="h-1 w-10 rounded-full bg-fp-600 mb-4"></div>
      <div class="font-serif font-bold text-[18px]">Crea tu PIN personal</div>
      <p class="text-[12.5px] text-mut mt-1 mb-4">Por seguridad, en tu primer ingreso debes definir un PIN nuevo, personal e intransferible (mínimo 6 caracteres).</p>
      <div class="space-y-3">
        <input v-model="np1" type="password" class="inp" placeholder="Nuevo PIN">
        <input v-model="np2" type="password" class="inp" placeholder="Repetir nuevo PIN">
        <div v-if="pinErr" class="errbx text-[12.5px]">{{ pinErr }}</div>
        <button class="btn-p w-full" :disabled="pinBusy" @click="guardar">{{ pinBusy ? 'Guardando…' : 'Guardar y continuar' }}</button>
      </div>
    </div>
  </div>
</template>
