import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { VitePWA } from 'vite-plugin-pwa';
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

/* Versión desplegada: número de package.json + commit corto + fecha de compilación.
   Se inyectan en tiempo de compilación y se muestran en Acceso, Mi cuenta y la barra superior. */
const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));
let commit = 'sin-git';
try { commit = execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch {}
const fechaBuild = new Intl.DateTimeFormat('es-DO', {
  timeZone: 'America/Santo_Domingo', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false
}).format(new Date());

// base './' → el portal funciona en cualquier carpeta del servidor (p. ej. /delegados/)
export default defineConfig({
  base: './',
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __APP_COMMIT__:  JSON.stringify(commit),
    __APP_FECHA__:   JSON.stringify(fechaBuild)
  },
  plugins: [
    vue(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/apple-touch-icon.png', 'instructivo.pdf'],
      manifest: {
        name: 'Portal de Delegados FP 2028',
        short_name: 'Delegados FP',
        description: 'Preselección de delegados, suplentes y observadores de escrutinio · Secretaría Nacional Electoral · Fuerza del Pueblo',
        id: './',
        start_url: './',
        scope: './',
        display: 'standalone',
        orientation: 'portrait',
        lang: 'es-DO',
        background_color: '#FBFBF9',
        theme_color: '#1D8A55',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
        ]
      },
      workbox: {
        navigateFallback: 'index.html',
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.hostname.endsWith('.supabase.co'),
            handler: 'NetworkOnly'
          },
          {
            urlPattern: ({ url }) => url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com',
            handler: 'StaleWhileRevalidate',
            options: { cacheName: 'fuentes', expiration: { maxEntries: 12, maxAgeSeconds: 60 * 60 * 24 * 180 } }
          }
        ]
      }
    })
  ]
});
