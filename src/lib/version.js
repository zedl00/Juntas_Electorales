/* src/lib/version.js
   Versión desplegada. Los tres valores los inyecta vite.config.js al compilar. */
export const APP_VERSION = __APP_VERSION__;   // 8.7.0 (package.json)
export const APP_COMMIT  = __APP_COMMIT__;    // commit corto de git
export const APP_FECHA   = __APP_FECHA__;     // fecha y hora de compilación (Santo Domingo)

export const versionCorta = 'v' + APP_VERSION;
export const versionLarga = `v${APP_VERSION} · ${APP_COMMIT} · compilado ${APP_FECHA}`;
