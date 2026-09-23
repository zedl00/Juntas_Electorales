import { ref } from 'vue';
import { t } from './toasts';

export const showInstall = ref(false);
export const showIos = ref(false);
export const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);
export const enApp = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

let deferredPrompt = null;

export function initPwa() {
  window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); deferredPrompt = e; showInstall.value = true; });
  window.addEventListener('appinstalled', () => { showInstall.value = false; t('Aplicación instalada', 'ok'); });
}

export async function instalar() {
  if (deferredPrompt) {
    deferredPrompt.prompt();
    try { await deferredPrompt.userChoice; } catch (e) { /* cancelado */ }
    deferredPrompt = null; showInstall.value = false; return;
  }
  if (isIos) { showIos.value = true; return; }
  t('En el menú del navegador elige "Instalar aplicación".');
}
