<!-- src/components/TopBar.vue -->
<script setup>
import { useRouter } from 'vue-router';
import { perfil, iniciales } from '../stores/auth';
import { rolLbl } from '../lib/constantes';
import { showInstall, isIos, enApp, instalar } from '../stores/pwa';
import { versionCorta } from '../lib/version';

const router = useRouter();
</script>

<template>
  <header class="sticky top-0 z-40 bg-white/95 backdrop-blur border-b border-line">
    <div class="mx-auto max-w-[1600px] px-4 sm:px-6 h-14 flex items-center justify-between gap-3">
      <div class="flex items-center gap-2.5 min-w-0">
        <div class="w-8 h-8 rounded-lg bg-fp-600 text-white grid place-items-center font-bold text-[13px] shrink-0">FP</div>
        <div class="min-w-0">
          <div class="font-serif font-bold text-[15px] leading-tight truncate">Delegados 2028</div>
          <div class="text-[10px] text-mut leading-tight hidden sm:block">Secretaría Nacional Electoral · {{ versionCorta }}</div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <button v-if="showInstall || (isIos && !enApp)" class="btn-o btn-s hidden sm:inline-flex" @click="instalar">Instalar app</button>
        <button class="flex items-center gap-2 rounded-xl border border-line bg-white pl-1.5 pr-3 py-1.5 hover:border-fp-300" @click="router.push('/cuenta')">
          <span class="w-7 h-7 rounded-lg bg-fp-50 text-fp-800 grid place-items-center text-[11px] font-bold">{{ iniciales }}</span>
          <span class="text-left hidden sm:block">
            <span class="block text-[12px] font-semibold leading-tight max-w-[140px] truncate">{{ perfil?.nombre }}</span>
            <span class="block text-[10px] text-mut leading-tight">{{ rolLbl[perfil?.rol] }}</span>
          </span>
        </button>
      </div>
    </div>
  </header>
</template>
