<!-- src/App.vue -->
<script setup>
import { watch } from 'vue';
import { useRoute } from 'vue-router';
import { sesion, perfil } from './stores/auth';
import { cargarCat } from './stores/catalogo';
import { refrescar } from './stores/kpi';
import { printJob, cargarDocsCfg } from './stores/print';
import AppToasts from './components/AppToasts.vue';
import TopBar from './components/TopBar.vue';
import CintaAvance from './components/CintaAvance.vue';
import SideNav from './components/SideNav.vue';
import TabsMovil from './components/TabsMovil.vue';
import ModalPin from './components/ModalPin.vue';
import ModalIdentidad from './components/ModalIdentidad.vue';
import ModalIos from './components/ModalIos.vue';
import PrintOverlay from './components/PrintOverlay.vue';

const route = useRoute();

/* Al obtener perfil (login o sesión restaurada): cargar catálogo y KPI una sola vez */
watch(perfil, p => { if (p) { cargarCat(); refrescar(); cargarDocsCfg(); } }, { immediate: true });
</script>

<template>
  <AppToasts />

  <!-- Acceso (sin sesión) -->
  <RouterView v-if="!sesion || route.name === 'acceso'" />

  <!-- Aplicación -->
  <div v-else id="shell" class="min-h-screen flex flex-col">
    <TopBar />
    <CintaAvance />
    <!-- Confirmación de la SNE pendiente (fase 74): consulta sí, registra no -->
    <div v-if="perfil?.confirmacion_pendiente" class="bg-amber-50 border-b border-amber-200 text-amber-900 text-[12.5px] px-4 sm:px-6 py-2 text-center">
      Tu acceso está <b>pendiente de confirmación por la Comisión</b>. Puedes consultar; podrás registrar cuando la SNE confirme tu identidad.
    </div>
    <div class="mx-auto max-w-[1600px] w-full px-4 sm:px-6 flex-1 flex gap-6 py-5 pb-24 lg:pb-8">
      <SideNav />
      <main class="flex-1 min-w-0">
        <RouterView v-slot="{ Component }">
          <KeepAlive include="InicioView,RegistrarView,PostulantesView">
            <component :is="Component" />
          </KeepAlive>
        </RouterView>
      </main>
    </div>
    <TabsMovil />
  </div>

  <ModalIdentidad />
  <ModalPin />
  <ModalIos />
  <PrintOverlay v-if="printJob" />
</template>
