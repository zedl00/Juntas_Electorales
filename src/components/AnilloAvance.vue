<script setup>
import { computed } from 'vue';

const props = defineProps({
  pct: { type: Number, default: 0 },
  size: { type: Number, default: 88 },
  grosor: { type: Number, default: 10 },
  claro: { type: Boolean, default: false }   // sobre fondo verde
});

const r = computed(() => (props.size / 2) - (props.grosor / 2));
const circ = computed(() => 2 * Math.PI * r.value);
const offset = computed(() => circ.value * (1 - Math.min(Math.max(props.pct, 0), 100) / 100));
const color = computed(() => {
  if (props.claro) return '#9FE1CB';
  if (props.pct >= 60) return '#1D8A55';
  if (props.pct >= 25) return '#D9820A';
  return '#DC2626';
});
</script>

<template>
  <svg :width="size" :height="size" :viewBox="`0 0 ${size} ${size}`" class="shrink-0"
       role="img" :aria-label="'Avance ' + pct + ' por ciento'">
    <circle :cx="size/2" :cy="size/2" :r="r" fill="none"
            :stroke="claro ? 'rgba(255,255,255,.22)' : '#E8EFEA'" :stroke-width="grosor" />
    <circle :cx="size/2" :cy="size/2" :r="r" fill="none"
            :stroke="color" :stroke-width="grosor" stroke-linecap="round"
            :stroke-dasharray="circ" :stroke-dashoffset="offset"
            :transform="`rotate(-90 ${size/2} ${size/2})`"
            style="transition: stroke-dashoffset .7s cubic-bezier(.4,0,.2,1)" />
    <text :x="size/2" :y="size/2 + size*0.075" text-anchor="middle"
          :fill="claro ? '#E1F5EE' : '#1A1A1A'"
          :font-size="size * 0.27" font-weight="700" font-family="inherit">{{ pct }}%</text>
  </svg>
</template>
