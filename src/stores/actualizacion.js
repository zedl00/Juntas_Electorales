/* src/stores/actualizacion.js · fase 89
   Actualización automática de la app instalada.
   - Registra el service worker y comprueba si hay versión nueva al abrir, cada hora y al volver a
     primer plano. Cuando la nueva toma el control, la página se recarga sola (registerType autoUpdate).
   - «Versión mínima» (Gestión → Configuración → Seguridad del acceso): si esta copia es más vieja,
     descarta lo guardado y se recarga. Protegido contra bucles: un intento cada 2 minutos. */
import { registerSW } from 'virtual:pwa-register';
import { APP_VERSION } from '../lib/version';
import { t } from './toasts';

let registro = null;
const UPD_KEY = 'portal_upd';

export function iniciarActualizacion() {
  if (!('serviceWorker' in navigator)) return;
  registerSW({
    immediate: true,
    onRegisteredSW(_url, r) {
      registro = r || null;
      if (!r) return;
      setInterval(() => { try { r.update(); } catch (e) { /* sin conexión */ } }, 60 * 60 * 1000);
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') { try { r.update(); } catch (e) { /* sin conexión */ } } });
    }
  });
}

/* Compara versiones "8.13.0": negativo si a < b */
export function compararVersion(a, b) {
  const pa = String(a || '0').split('.').map(n => parseInt(n, 10) || 0);
  const pb = String(b || '0').split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) { const d = (pa[i] || 0) - (pb[i] || 0); if (d) return d; }
  return 0;
}

/** Si la versión instalada es menor que la mínima, fuerza la actualización. Devuelve true si la inició. */
export async function comprobarVersion(minima) {
  if (!minima || compararVersion(APP_VERSION, minima) >= 0) return false;
  let ultimo = 0;
  try { ultimo = parseInt(sessionStorage.getItem(UPD_KEY) || '0', 10) || 0; } catch (e) { /* sin almacenamiento */ }
  if (Date.now() - ultimo < 2 * 60 * 1000) { t('Hay una versión nueva del portal (' + minima + '). Cierra la app por completo y vuelve a abrirla.', 'err'); return false; }
  try { sessionStorage.setItem(UPD_KEY, String(Date.now())); } catch (e) { /* sin almacenamiento */ }
  t('Actualizando el portal a la versión ' + minima + '…');
  try {
    if (registro) { try { await registro.update(); } catch (e) { /* sigue */ } }
    const regs = await navigator.serviceWorker?.getRegistrations?.() || [];
    await Promise.all(regs.map(r => r.unregister()));
    if (window.caches) { const ks = await caches.keys(); await Promise.all(ks.map(k => caches.delete(k))); }
  } catch (e) { /* se recarga igual */ }
  const u = new URL(location.href); u.searchParams.set('v', minima);
  location.replace(u.toString());
  return true;
}
