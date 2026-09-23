<!-- src/views/CuentaView.vue -->
<script setup>
import { sb } from '../lib/supabase';
import { regiones, provsOf } from '../stores/catalogo';
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { perfil, guardarPin, logout , esAdmin } from '../stores/auth';
import { rolLbl } from '../lib/constantes';
import { fmt, fmtCed, fecha } from '../lib/formato';
import { showInstall, isIos, enApp, instalar } from '../stores/pwa';
import { t } from '../stores/toasts';
import { versionLarga } from '../lib/version';

const router = useRouter();
const cp1 = ref(''), cp2 = ref(''), cpBusy = ref(false);

const cambiarPin = async () => {
  if (String(cp1.value).length < 6) { t('El PIN debe tener al menos 6 caracteres.', 'err'); return; }
  if (cp1.value !== cp2.value) { t('Los PIN no coinciden.', 'err'); return; }
  cpBusy.value = true;
  const err = await guardarPin(cp1.value);
  cpBusy.value = false;
  if (err) { t(err, 'err'); return; }
  cp1.value = ''; cp2.value = '';
  t('PIN actualizado', 'ok');
};

const diag = ref(null), diagBusy = ref(false);
const correrDiag = async () => {
  diagBusy.value = true; const r = {};
  r.reg = regiones.value.length
    ? { ok: true,  titulo: 'Regiones (fase 4)', det: regiones.value.join(' · ') }
    : { ok: false, titulo: 'Regiones (fase 4)', det: 'Vacías → ejecutar fase4_distritos_y_regiones.sql' };
  const pr = provsOf('');
  r.prov = pr.length
    ? { ok: true,  titulo: 'Provincias enlazadas', det: pr.length + ' provincias (' + pr.slice(0, 3).map(p => p.nombre).join(', ') + '…)' }
    : { ok: false, titulo: 'Provincias enlazadas', det: 'Vacías → ejecutar fase6_cierre_definitivo.sql' };
  const d1 = await sb.from('portal_distritos').select('municipio_id').limit(1);
  r.dist = d1.error ? { ok: false, titulo: 'Distritos (fase 4)', det: d1.error.message + ' → ejecutar fase6_cierre_definitivo.sql' }
                    : { ok: true,  titulo: 'Distritos (fase 4)', det: 'Vista disponible' };
  const d2 = await sb.rpc('portal_cobertura_colegios', { p_municipio: 0, p_jce: null });
  r.cob = d2.error ? { ok: false, titulo: 'Cobertura por colegio', det: d2.error.message }
                   : { ok: true,  titulo: 'Cobertura por colegio', det: 'Función activa' };
  const d3 = await sb.rpc('portal_eventos', { p_limit: 1 });
  r.bit = d3.error ? { ok: false, titulo: 'Bitácora (fase 2)', det: d3.error.message + ' → ejecutar fase2' }
                   : { ok: true,  titulo: 'Bitácora (fase 2)', det: 'Activa' };
  const d4 = await sb.from('postulantes_2028').select('militancia').limit(1);
  r.f5 = d4.error ? { ok: false, titulo: 'Fase 5', det: 'Pendiente → ejecutar fase5_consulta_bot_y_ajustes.sql' }
                  : { ok: true,  titulo: 'Fase 5', det: 'Militancia, rol consulta y bot listos' };
  const dg = await sb.rpc('portal_diag');
  r.est = dg.error
    ? { ok: false, titulo: 'Estructura territorial', det: dg.error.message + ' → ejecutar fase11_asignacion_unica.sql' }
    : { ok: (dg.data?.muns_con_varios ?? 0) > 0,
        titulo: 'Estructura territorial',
        det: dg.data
          ? `${dg.data.municipios} municipios · ${dg.data.distritos} distritos municipales · ${dg.data.circunscripciones} circunscripciones · ${dg.data.muns_con_varios} municipios con varias demarcaciones · colegios ubicados ${Number(dg.data.colegios_ubicados || 0).toLocaleString('es-DO')} de ${Number(dg.data.colegios_total || 0).toLocaleString('es-DO')} · meta ${Number(dg.data.meta_nacional || 0).toLocaleString('es-DO')}` +
            (dg.data.ejemplo_multi ? ` · ej.: ${dg.data.ejemplo_multi.municipio} con ${dg.data.ejemplo_multi.demarcaciones} demarcaciones` : '')
          : '' };
  const d5 = await sb.from('postulantes_2028').select('id', { count: 'exact', head: true }).is('provincia_id', null);
  r.geo = (d5.count ?? 0) > 0
    ? { ok: false, titulo: 'Georreferencia de postulantes', det: d5.count + ' sin provincia → ejecutar fase6_cierre_definitivo.sql' }
    : { ok: true,  titulo: 'Georreferencia de postulantes', det: 'Todos con provincia y región (filtros de Postulantes operativos)' };
  diag.value = r; diagBusy.value = false;
};
</script>

<template>
  <section class="max-w-xl space-y-4">
    <h2 class="font-serif text-xl font-bold">Mi cuenta</h2>
    <div class="card p-5">
      <div class="font-serif font-bold text-[17px]">{{ perfil?.nombre }}</div>
      <div class="text-[12.5px] text-mut mt-0.5">{{ fmtCed(perfil?.cedula) }} · {{ rolLbl[perfil?.rol] }}</div>
      <div class="mt-3 flex flex-wrap gap-2">
        <span v-if="perfil?.municipio" class="chip">{{ perfil.municipio }} · {{ perfil.provincia }}</span>
        <span v-else-if="perfil?.provincia" class="chip">Provincia {{ perfil.provincia }}</span>
        <span v-else-if="perfil?.region" class="chip">Región {{ perfil.region }}</span>
        <span v-else class="chip">Alcance nacional</span>
        <span v-if="perfil?.meta" class="badge border-line bg-white text-mut">Meta del territorio: {{ fmt(perfil.meta) }}</span>
      </div>
    </div>
    <div class="card p-5">
      <h3 class="font-serif font-bold text-[15px] mb-3">Cambiar PIN</h3>
      <div class="grid sm:grid-cols-2 gap-3">
        <input v-model="cp1" type="password" class="inp" placeholder="Nuevo PIN (mín. 6)">
        <input v-model="cp2" type="password" class="inp" placeholder="Repetir nuevo PIN">
      </div>
      <button class="btn-p mt-3" :disabled="cpBusy" @click="cambiarPin">{{ cpBusy ? 'Guardando…' : 'Actualizar PIN' }}</button>
    </div>
    <div class="card p-5 flex items-center justify-between gap-3">
      <div>
        <div class="font-semibold text-sm">Instructivo oficial</div>
        <div class="text-[12px] text-mut">{{ perfil?.acuse_instructivo ? 'Acuse registrado el ' + fecha(perfil.acuse_instructivo) : 'Aún no has registrado tu acuse de lectura' }}</div>
      </div>
      <button class="btn-o btn-s" @click="router.push('/protocolo')">Ver protocolo</button>
    </div>
    <div v-if="showInstall || (isIos && !enApp)" class="card p-5 flex items-center justify-between gap-3">
      <div><div class="font-semibold text-sm">Aplicación móvil</div><div class="text-[12px] text-mut">Instálala para acceso directo desde tu pantalla de inicio.</div></div>
      <button class="btn-p btn-s" @click="instalar">Instalar</button>
    </div>
    <div v-if="esAdmin" class="card p-5">
      <div class="flex items-center justify-between gap-3 mb-1">
        <div><div class="font-semibold text-sm">Diagnóstico del sistema</div><div class="text-[12px] text-mut">Verifica en un clic que las fases SQL están activas en la base de datos.</div></div>
        <button class="btn-o btn-s" @click="correrDiag" :disabled="diagBusy">{{ diagBusy ? 'Verificando…' : 'Verificar' }}</button>
      </div>
      <div v-if="diag" class="space-y-1 mt-2 text-[12.5px]">
        <div v-for="(v, k) in diag" :key="k" class="flex gap-2 items-baseline">
          <span :class="v.ok ? 'text-fp-700' : 'text-red-600'" class="font-bold w-3">{{ v.ok ? '✓' : '✗' }}</span>
          <span class="font-semibold w-40 shrink-0">{{ v.titulo }}</span>
          <span class="text-mut">{{ v.det }}</span>
        </div>
      </div>
    </div>

    <div class="card p-5 flex items-center justify-between gap-3">
      <div><div class="font-semibold text-sm">Centro de ayuda</div><div class="text-[12px] text-mut">Cómo funciona tu acceso, tu PIN y el sistema, explicado paso a paso.</div></div>
      <button class="btn-o btn-s" @click="router.push('/ayuda')">Abrir ayuda</button>
    </div>
    <button class="btn-o w-full" @click="logout">Cerrar sesión</button>
    <p class="text-center text-[11px] text-mut">Portal de Delegados 2028 · {{ versionLarga }} · Comisión de Juntas Electorales y OCLEE — SNE·FP</p>
  </section>
</template>
