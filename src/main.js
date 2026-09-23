import { createApp } from 'vue';
import App from './App.vue';
import { router } from './router';
import { inicializarAuth } from './stores/auth';
import { initPwa } from './stores/pwa';
import './style.css';

initPwa();
inicializarAuth();               // restaura la sesión; el router espera authReady
createApp(App).use(router).mount('#app');
