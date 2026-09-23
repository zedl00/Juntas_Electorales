<script setup>
import { showIos } from '../stores/pwa';
</script>

<template>
  <div v-if="showIos" class="modal fixed inset-0 z-[70] bg-ink/50 p-4 flex items-center justify-center" @click.self="showIos = false">
    <div class="card w-full max-w-sm p-5">
      <div class="font-serif font-bold text-[17px] mb-2">Instalar en iPhone</div>
      <ol class="text-[13px] space-y-2 list-decimal pl-5 leading-relaxed">
        <li>Abre este portal en <b>Safari</b>.</li>
        <li>Toca el botón <b>Compartir</b> <span class="inline-block border border-line rounded px-1 text-[11px]">⬆︎</span> en la barra inferior.</li>
        <li>Elige <b>“Agregar a pantalla de inicio”</b>.</li>
        <li>Confirma con <b>Agregar</b>. Verás el ícono FP en tu pantalla.</li>
      </ol>
      <button class="btn-p w-full mt-4" @click="showIos = false">Entendido</button>
    </div>
  </div>
</template>
