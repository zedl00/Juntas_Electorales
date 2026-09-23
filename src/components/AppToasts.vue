<script setup>
import { toasts } from '../stores/toasts';
</script>

<template>
  <div class="toastwrap fixed top-3 inset-x-0 z-[90] flex flex-col items-center gap-2 px-4 pointer-events-none">
    <div v-for="ts in toasts" :key="ts.id"
         class="pointer-events-auto rounded-xl border px-4 py-2.5 text-sm font-medium shadow-sm max-w-md w-full sm:w-auto"
         :class="ts.tipo==='err' ? 'bg-red-50 border-red-200 text-red-800' : (ts.tipo==='ok' ? 'bg-fp-50 border-fp-200 text-fp-900' : 'bg-white border-line text-ink')">
      {{ ts.msg }}
    </div>
  </div>
</template>
