/* src/router/index.js */
import { createRouter, createWebHashHistory } from 'vue-router';
import { authReady, sesion, esAdmin } from '../stores/auth';

/* Rutas con hash (#/inicio): funcionan en cPanel sin configurar el servidor. */
const routes = [
  { path: '/', redirect: '/inicio' },
  { path: '/acceso',      name: 'acceso',      component: () => import('../views/AccesoView.vue'),      meta: { publica: true } },
  { path: '/inicio',      name: 'inicio',      component: () => import('../views/InicioView.vue') },
  { path: '/registrar',   name: 'registrar',   component: () => import('../views/RegistrarView.vue') },
  { path: '/postulantes', name: 'postulantes', component: () => import('../views/PostulantesView.vue') },
  { path: '/protocolo',   name: 'protocolo',   component: () => import('../views/ProtocoloView.vue') },
  { path: '/usuarios',    name: 'usuarios',    component: () => import('../views/UsuariosView.vue'),    meta: { admin: true } },
  { path: '/dirigencia',  name: 'dirigencia',  component: () => import('../views/DirigenciaView.vue'),  meta: { admin: true } },
  { path: '/idoneidad',   name: 'idoneidad',   component: () => import('../views/IdoneidadView.vue') },
  { path: '/asignacion',  name: 'asignacion',  component: () => import('../views/AsignacionView.vue') },
  { path: '/actividad',   name: 'actividad',   component: () => import('../views/ActividadView.vue'),   meta: { admin: true } },
  { path: '/cuenta',      name: 'cuenta',      component: () => import('../views/CuentaView.vue') },
  { path: '/ayuda',       name: 'ayuda',       component: () => import('../views/AyudaView.vue'),       meta: { publica: true } },
  { path: '/:pathMatch(.*)*', redirect: '/inicio' }
];

export const router = createRouter({ history: createWebHashHistory(), routes });

router.beforeEach(async to => {
  await authReady;
  if (!to.meta.publica && !sesion.value) return { name: 'acceso' };
  if (to.name === 'acceso' && sesion.value) return { name: 'inicio' };
  if (to.meta.admin && !esAdmin.value) return { name: 'inicio' };
  return true;
});

router.afterEach(() => { window.scrollTo({ top: 0 }); });
