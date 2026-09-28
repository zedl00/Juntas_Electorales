<!-- src/components/SideNav.vue -->
<script setup>
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { esAdmin, perfil, vePostulantes } from '../stores/auth';
import { sinColegio } from '../stores/kpi';

const route = useRoute();
const router = useRouter();
const items = [
  { r: 'inicio',      ic: '◈', txt: 'Inicio' },
  { r: 'avance',      ic: '▤', txt: 'Avance' },
  { r: 'registrar',   ic: '✎', txt: 'Registrar' },
  { r: 'postulantes', ic: '☰', txt: 'Postulantes', ver: true },
  { r: 'asignacion',  ic: '⊞', txt: 'Asignación', roles: ['admin_sne','coordinador_regional'], ver: true },   // por ahora solo SNE y regionales
  { r: 'protocolo',   ic: '§', txt: 'Protocolo' },
  { r: 'dirigencia',  ic: '⬡', txt: 'Dirigencia', admin: true },
  { g: 'gestion',     ic: '⚙', txt: 'Gestión', admin: true,
    hijos: [
      { r: 'usuarios',  ic: '♟', txt: 'Usuarios' },
      { r: 'actividad', ic: '☷', txt: 'Actividad' }
    ] },
  { r: 'cuenta',      ic: '◉', txt: 'Mi cuenta' },
  { r: 'ayuda',       ic: 'ⓘ', txt: 'Ayuda' }
];

/* Gestión se abre sola cuando estás dentro de una de sus pantallas */
const abierto = ref(false);
watch(() => route.name, n => {
  if (['usuarios','actividad'].includes(n)) abierto.value = true;
}, { immediate: true });
</script>

<template>
  <aside class="hidden lg:block w-56 shrink-0">
    <nav class="sticky top-[124px] space-y-1">
      <template v-for="it in items" :key="it.r || it.g">
        <!-- Grupo desplegable -->
        <template v-if="it.hijos">
          <div v-if="!it.admin || esAdmin" class="navi justify-between" @click="abierto = !abierto">
            <span><span>{{ it.ic }}</span> {{ it.txt }}</span>
            <span class="text-[10px] transition-transform" :class="abierto ? 'rotate-90' : ''">›</span>
          </div>
          <div v-if="(!it.admin || esAdmin) && abierto" class="pl-3">
            <div v-for="h in it.hijos" :key="h.r" class="navi text-[13px]"
                 :class="{ 'navi-on': route.name === h.r }" @click="router.push({ name: h.r })">
              <span>{{ h.ic }}</span> {{ h.txt }}
            </div>
          </div>
        </template>

        <!-- Entrada simple -->
        <div v-else-if="(!it.admin || esAdmin) && (!it.roles || it.roles.includes(perfil?.rol)) && (!it.ver || vePostulantes)" class="navi" :class="{ 'navi-on': route.name === it.r }" @click="router.push({ name: it.r })">
          <span>{{ it.ic }}</span> {{ it.txt }}
          <span v-if="it.r === 'asignacion' && sinColegio" class="ml-auto badge border-amber-300 bg-amber-50 text-amber-800 !py-0" title="Esperan colegio">{{ sinColegio }}</span>
        </div>
      </template>
    </nav>
  </aside>
</template>
