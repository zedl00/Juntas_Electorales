<!-- src/components/CintaAvance.vue -->
<script setup>
import { ribbon } from '../stores/auth';
import { kpi, avancePct } from '../stores/kpi';
import { fmt } from '../lib/formato';
</script>

<template>
  <div class="bg-fp-25 border-b border-fp-100">
    <div class="mx-auto max-w-[1600px] px-4 sm:px-6 py-2.5 flex items-center justify-between gap-4">
      <div class="min-w-0">
        <div class="font-serif font-bold text-[14px] leading-tight truncate">{{ ribbon.titulo }}</div>
        <div class="text-[11px] text-mut leading-tight truncate">{{ ribbon.sub }}</div>
      </div>
      <div class="w-40 sm:w-64 shrink-0">
        <div class="flex items-baseline justify-between text-[11px] mb-1">
          <span class="font-bold text-fp-800">{{ fmt(kpi?.total ?? 0) }}</span>
          <span class="text-mut">de {{ fmt(kpi?.meta ?? 0) }} · {{ avancePct }}%</span>
        </div>
        <div class="h-[3px] rounded-full bg-fp-100 overflow-hidden">
          <div class="h-full bg-fp-600 bar-anim" :style="{ width: Math.min(avancePct, 100) + '%' }"></div>
        </div>
      </div>
    </div>
  </div>
</template>
