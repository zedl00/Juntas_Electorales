import { createApp } from 'vue';
import App from './App.vue';
import { router } from './router';
import { inicializarAuth } from './stores/auth';
import { initPwa } from './stores/pwa';
import { iniciarActualizacion } from './stores/actualizacion';
import './style.css';

initPwa();
iniciarActualizacion();         // service worker: comprueba versión nueva al abrir, cada hora y al volver
inicializarAuth();               // restaura la sesión; el router espera authReady
createApp(App).use(router).mount('#app');
