<script setup>
import { useRoute, useRouter } from 'vue-router';
import { canRegister, vePostulantes } from '../stores/auth';
import { t } from '../stores/toasts';

const route = useRoute();
const router = useRouter();
const tapRegistrar = () => {
  if (!canRegister.value) { t('El registro en plataforma corresponde al Encargado(a) Electoral.', 'err'); router.push(vePostulantes.value ? '/postulantes' : '/avance'); }
  else router.push('/registrar');
};
</script>

<template>
  <nav class="lg:hidden fixed bottom-0 inset-x-0 z-40 bg-white/95 backdrop-blur border-t border-line safe-b">
    <div class="grid grid-cols-5 h-[60px] max-w-lg mx-auto">
      <button class="tabb" :class="{ '!text-fp-700': route.name === 'inicio' }" @click="router.push('/inicio')"><span class="text-[17px]">◈</span>Inicio</button>
      <button v-if="vePostulantes" class="tabb" :class="{ '!text-fp-700': route.name === 'postulantes' }" @click="router.push('/postulantes')"><span class="text-[17px]">☰</span>Postulantes</button>
      <button v-else class="tabb" :class="{ '!text-fp-700': route.name === 'avance' }" @click="router.push('/avance')"><span class="text-[17px]">▤</span>Avance</button>
      <button class="relative -mt-4" @click="tapRegistrar">
        <span class="mx-auto w-12 h-12 rounded-2xl bg-fp-600 text-white grid place-items-center text-xl shadow-lg shadow-fp-600/25">✎</span>
        <span class="block text-[10px] font-semibold text-mut mt-0.5">Registrar</span>
      </button>
      <button class="tabb" :class="{ '!text-fp-700': route.name === 'protocolo' }" @click="router.push('/protocolo')"><span class="text-[17px]">§</span>Protocolo</button>
      <button class="tabb" :class="{ '!text-fp-700': route.name === 'cuenta' || route.name === 'usuarios' }" @click="router.push('/cuenta')"><span class="text-[17px]">◉</span>Cuenta</button>
    </div>
  </nav>
</template>
