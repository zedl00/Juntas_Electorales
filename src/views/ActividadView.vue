<!-- src/views/ActividadView.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { sb } from '../lib/supabase';
import { fechaHora } from '../lib/formato';
import { t } from '../stores/toasts';

const eventos = ref([]);
const busy = ref(false);
const fAccion = ref('');
const fQ = ref('');
const abierto = ref(null);

const accionLbl = {
  acceso: 'Acceso al portal', ingreso: 'Ingreso con PIN', sesion_duplicada: 'Intento con sesión abierta', sesion_cerrada: 'Sesión cerrada por la Comisión', sesion_inactiva: 'Sesión cerrada por inactividad', gancho_error: 'Error en el gancho de sesión',
  consulta_padron: 'Consulta de padrón',
  registro: 'Registro de postulante', edicion: 'Edición de postulante',
  cambio_estado: 'Cambio de etapa', eliminacion: 'Eliminación de postulante',
  alta_usuario: 'Alta de usuario', edicion_usuario: 'Edición de usuario',
  usuario_activado: 'Usuario activado', usuario_desactivado: 'Usuario desactivado',
  reset_pin: 'PIN restablecido', identidad_reiniciada: 'Verificación de identidad reiniciada',
  consulta_bot: 'Consulta por asistente',
  impresion: 'Documento impreso',
  bot_no_autorizado: 'Intento no autorizado',
  baja_usuario: 'Baja de usuario',
  exportacion: 'Exportación de datos', impresion_denegada: 'Impresión denegada', acceso_ip_bloqueada: 'Conexión bloqueada por intentos',
  bloqueo_temporal: 'Bloqueo temporal', bloqueo_definitivo: 'Bloqueo definitivo', pin_vencido: 'PIN inicial vencido', solicitud_pin: 'Solicitud de PIN',
  modo_emergencia: 'Modo de emergencia', config_seguridad: 'Configuración de seguridad', verif_lote: 'Lote de verificación', verif_resultados: 'Resultados de verificación',
  api_cliente_alta: 'Clave de API creada', api_cliente_revocado: 'Clave de API revocada'
};
const accionCls = {
  acceso: 'border-line bg-white text-mut', ingreso: 'border-line bg-white text-mut', sesion_duplicada: 'border-red-200 bg-red-50 text-red-700', sesion_cerrada: 'border-amber-200 bg-amber-50 text-amber-800', sesion_inactiva: 'border-line bg-paper text-ink', gancho_error: 'border-red-200 bg-red-50 text-red-700',
  consulta_padron: 'border-sky-200 bg-sky-50 text-sky-800',
  registro: 'border-fp-200 bg-fp-50 text-fp-800', edicion: 'border-line bg-paper text-ink',
  cambio_estado: 'border-fp-600 bg-fp-600 text-white', eliminacion: 'border-red-200 bg-red-50 text-red-700',
  alta_usuario: 'border-fp-200 bg-fp-50 text-fp-800', edicion_usuario: 'border-line bg-paper text-ink',
  usuario_activado: 'border-fp-200 bg-fp-50 text-fp-800', usuario_desactivado: 'border-amber-200 bg-amber-50 text-amber-800',
  reset_pin: 'border-amber-200 bg-amber-50 text-amber-800', identidad_reiniciada: 'border-amber-200 bg-amber-50 text-amber-800',
  consulta_bot: 'border-sky-200 bg-sky-50 text-sky-800',
  impresion: 'border-line bg-paper text-ink/70',
  bot_no_autorizado: 'border-red-200 bg-red-50 text-red-700',
  baja_usuario: 'border-red-200 bg-red-50 text-red-700',
  exportacion: 'border-amber-200 bg-amber-50 text-amber-800', impresion_denegada: 'border-red-200 bg-red-50 text-red-700', acceso_ip_bloqueada: 'border-red-200 bg-red-50 text-red-700',
  bloqueo_temporal: 'border-amber-200 bg-amber-50 text-amber-800', bloqueo_definitivo: 'border-red-200 bg-red-50 text-red-700', pin_vencido: 'border-amber-200 bg-amber-50 text-amber-800', solicitud_pin: 'border-line bg-paper text-ink',
  modo_emergencia: 'border-red-600 bg-red-600 text-white', config_seguridad: 'border-line bg-paper text-ink', verif_lote: 'border-sky-200 bg-sky-50 text-sky-800', verif_resultados: 'border-sky-200 bg-sky-50 text-sky-800',
  api_cliente_alta: 'border-sky-200 bg-sky-50 text-sky-800', api_cliente_revocado: 'border-amber-200 bg-amber-50 text-amber-800'
};

const cargar = async () => {
  busy.value = true;
  const { data, error } = await sb.rpc('portal_eventos', { p_limit: 400 });
  busy.value = false;
  if (error) { t('No se pudo cargar la bitácora: ' + error.message, 'err'); return; }
  eventos.value = (data || []).map((e, i) => ({ ...e, _k: i }));
};
onMounted(cargar);

const visibles = computed(() => eventos.value.filter(e => {
  if (fAccion.value && e.accion !== fAccion.value) return false;
  const q = fQ.value.trim().toLowerCase();
  if (q && !((e.usuario || '').toLowerCase().includes(q) || (e.entidad_id || '').toLowerCase().includes(q) || String(e.detalle?.ip || '').includes(q) || String(e.detalle?.nombre || '').toLowerCase().includes(q))) return false;
  return true;
}));

const resumenDe = e => {
  const d = e.detalle || {};
  if (d.cambios && Object.keys(d.cambios).length) return 'Campos: ' + Object.keys(d.cambios).join(', ');
  if (e.accion === 'cambio_estado') return (d.estado_anterior || '—') + ' → ' + (d.estado_nuevo || '—');
  if (e.accion === 'consulta_padron') return d.encontrado ? 'Encontrada en padrón' : 'No encontrada';
  if (e.accion === 'impresion') return (d.documento || '') + (d.territorio ? ' · ' + d.territorio : '') + (d.registros != null ? ' · ' + d.registros + ' registros' : '');
  if (e.accion === 'consulta_bot') return (d.canal || '') + ' · ' + (d.quien || '') + (d.comando ? ' · «' + d.comando + '»' : '');
  if (e.accion === 'bot_no_autorizado') return 'Identificador no registrado' + (d.comando ? ' · «' + d.comando + '»' : '');
  if (e.accion === 'alta_usuario') return (d.nombre || '') + (d.rol ? ' · ' + d.rol : '');
  if (e.accion === 'registro') return d.numero ? 'Formulario ' + d.numero : '';
  if (e.accion === 'ingreso') return (d.nombre || '') + (d.ip ? ' · IP ' + d.ip : '') + (d.pais ? ' · ' + d.pais : '');
  if (e.accion === 'exportacion') return (d.tipo || '') + (d.registros != null ? ' · ' + d.registros + ' registros' : '') + (d.detalle ? ' · ' + d.detalle : '');
  if (e.accion === 'acceso_ip_bloqueada') return 'IP ' + (d.ip || e.entidad_id || '?') + (d.pais ? ' ' + d.pais : '') + ' · ' + (d.fallos || '?') + ' fallos en ' + (d.ventana_min || '?') + ' min';
  if (e.accion === 'modo_emergencia') return (d.modo === 'solo_admin' ? 'PORTAL CERRADO' : 'portal abierto') + ' · sesiones expulsadas ' + (d.sesiones_cerradas ?? 0) + ' · ' + (d.por || '');
  if (e.accion === 'bloqueo_temporal' || e.accion === 'bloqueo_definitivo') return (d.nombre || '') + (d.minutos ? ' · ' + d.minutos + ' min' : '') + (d.ip ? ' · IP ' + d.ip : '');
  if (e.accion === 'sesion_duplicada') return (d.nombre || '') + ' · intento desde IP ' + (d.ip || '?') + ' · sesión abierta desde ' + (d.sesion_desde ? fechaHora(d.sesion_desde) : '?') + (d.sesion_ip ? ' (IP ' + d.sesion_ip + ')' : '');
  if (e.accion === 'sesion_cerrada') return (d.nombre || '') + (d.sesion_ip ? ' · IP ' + d.sesion_ip : '');
  if (e.accion === 'sesion_inactiva') return (d.nombre || '') + ' · límite ' + (d.limite_min || '?') + ' min' + (d.ultima_senal ? ' · última señal ' + fechaHora(d.ultima_senal) : '');
  return '';
};
</script>

<template>
  <section class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <div>
        <h2 class="font-serif text-xl font-bold">Actividad del sistema</h2>
        <p class="text-[12.5px] text-mut mt-0.5">Bitácora completa: accesos, consultas, registros, ediciones y gestión de usuarios, con el detalle de antes y después.</p>
      </div>
      <button class="btn-o btn-s shrink-0" @click="cargar" :disabled="busy">{{ busy ? 'Cargando…' : 'Actualizar' }}</button>
    </div>

    <div class="card p-3.5 grid grid-cols-2 sm:grid-cols-3 gap-2">
      <input v-model="fQ" class="inp !py-2 text-[12.5px]" placeholder="Usuario, folio, cédula o IP…">
      <select v-model="fAccion" class="inp !py-2 text-[12.5px]">
        <option value="">Acción: todas</option>
        <option v-for="(l, k) in accionLbl" :key="k" :value="k">{{ l }}</option>
      </select>
      <div class="text-[11px] text-mut self-center">{{ visibles.length }} eventos mostrados</div>
    </div>

    <div class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[760px]">
          <thead class="bg-paper border-b border-line"><tr>
            <th class="th">Fecha</th><th class="th">Usuario</th><th class="th">Acción</th><th class="th">Referencia</th><th class="th">Detalle</th>
          </tr></thead>
          <tbody>
            <template v-for="e in visibles" :key="e._k">
              <tr class="border-b border-line/60 hover:bg-fp-25/50 cursor-pointer" @click="abierto = (abierto === e._k ? null : e._k)">
                <td class="td whitespace-nowrap text-[12px] text-mut">{{ fechaHora(e.created_at) }}</td>
                <td class="td font-semibold whitespace-nowrap">{{ e.usuario }}</td>
                <td class="td"><span class="badge" :class="accionCls[e.accion] || 'border-line bg-white text-mut'">{{ accionLbl[e.accion] || e.accion }}</span></td>
                <td class="td whitespace-nowrap text-[12.5px]"><span class="text-mut">{{ e.entidad }}</span> <b class="font-mono text-[12px]">{{ e.entidad_id || '' }}</b></td>
                <td class="td text-[12px] text-mut">{{ resumenDe(e) }}</td>
              </tr>
              <tr v-if="abierto === e._k" class="border-b border-line/60 bg-paper/70">
                <td colspan="5" class="px-4 py-3">
                  <pre class="text-[11px] leading-relaxed whitespace-pre-wrap break-all text-ink/80">{{ JSON.stringify(e.detalle, null, 2) }}</pre>
                </td>
              </tr>
            </template>
            <tr v-if="!visibles.length && !busy"><td colspan="5" class="td text-center text-mut py-10">Sin eventos con estos criterios.</td></tr>
            <tr v-if="busy"><td colspan="5" class="td text-center text-mut py-10">Cargando…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="px-4 py-2.5 text-[11px] text-mut border-t border-line">Se muestran los últimos 400 eventos. Toca una fila para ver el detalle completo (antes / después).</div>
    </div>
  </section>
</template>
