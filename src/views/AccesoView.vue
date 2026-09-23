<!-- src/views/AccesoView.vue -->
<script setup>
import { reactive, ref, onMounted, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { login } from '../stores/auth';
import { showInstall, isIos, instalar } from '../stores/pwa';
import { sb } from '../lib/supabase';
import { versionCorta } from '../lib/version';

const router = useRouter();
const lf = reactive({ acceso: '', pin: '' });
const loginBusy = ref(false), loginErr = ref('');
const pedirPin = ref(false), cedPin = ref(''), pinBusy = ref(false), okPin = ref('');
const solicitarPin = async () => {
  pinBusy.value = true;
  const { data } = await sb.rpc('portal_delegados_solicitar_pin', { p_cedula: cedPin.value });
  pinBusy.value = false;
  okPin.value = data?.mensaje || 'Solicitud enviada. La Comisión se comunicará contigo.';
  cedPin.value = '';
};

/* ── Captcha de Cloudflare (Turnstile) ──
   La administración lo activa o desactiva en Gestión → Usuarios → Seguridad del
   acceso (fase 60). La pantalla de acceso lee esa configuración sin sesión por
   la función pública portal_config_publica. El token es de un solo uso: tras
   cada intento se reinicia el reto. */
const TS_KEY = ref('');
const tsEl = ref(null), tsToken = ref(''), tsId = ref(null);
const tsRender = () => {
  if (!TS_KEY.value || !tsEl.value || !window.turnstile) return;
  tsId.value = window.turnstile.render(tsEl.value, {
    sitekey: TS_KEY.value, language: 'es', theme: 'light', size: 'flexible',
    callback: tok => { tsToken.value = tok; },
    'expired-callback': () => { tsToken.value = ''; },
    'error-callback':   () => { tsToken.value = ''; }
  });
};
onMounted(async () => {
  const { data } = await sb.schema('public').rpc('portal_config_publica');
  if (!data?.captcha_activo || !data?.captcha_site_key) return;
  TS_KEY.value = data.captcha_site_key;
  await nextTick();
  if (window.turnstile) { tsRender(); return; }
  const s = document.createElement('script');
  s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  s.async = true; s.onload = tsRender;
  document.head.appendChild(s);
});

const entrar = async () => {
  loginErr.value = '';
  if (TS_KEY.value && !tsToken.value) { loginErr.value = 'Completa la verificación de seguridad.'; return; }
  loginBusy.value = true;
  const err = await login(lf.acceso, lf.pin, tsToken.value);
  loginBusy.value = false;
  if (TS_KEY.value && window.turnstile && tsId.value !== null) { window.turnstile.reset(tsId.value); tsToken.value = ''; }
  if (err) { loginErr.value = err; return; }
  router.push('/inicio');
};
</script>

<template>
  <div id="loginv" class="min-h-screen flex flex-col items-center justify-center px-5 py-10">
    <div class="w-full max-w-sm">
      <div class="h-1 w-12 rounded-full bg-fp-600 mb-6"></div>
      <h1 class="font-serif text-[28px] font-bold leading-tight">Portal de Delegados</h1>
      <p class="text-sm text-mut mt-1.5 leading-relaxed">Colegios Electorales 2028<br>Secretaría Nacional Electoral · Fuerza del Pueblo</p>

      <form class="card p-5 mt-7 space-y-4" @submit.prevent="entrar">
        <div>
          <label class="lbl" for="lacc">Cédula</label>
          <input id="lacc" v-model="lf.acceso" class="inp" type="text" inputmode="text" autocomplete="username" placeholder="000-0000000-0" required>
        </div>
        <div>
          <label class="lbl" for="lpin">PIN</label>
          <input id="lpin" v-model="lf.pin" class="inp" type="password" autocomplete="current-password" placeholder="••••••" required>
        </div>
        <div v-if="loginErr" class="errbx">{{ loginErr }}</div>
        <div v-if="TS_KEY" ref="tsEl" class="min-h-[65px]"></div>
        <button class="btn-p w-full" :disabled="loginBusy">
          <span v-if="!loginBusy">Entrar</span><span v-else>Verificando…</span>
        </button>
      </form>

      <div v-if="showInstall || isIos" class="mt-5 flex justify-center">
        <button class="btn-o btn-s" @click="instalar">📲 Instalar la aplicación en este teléfono</button>
      </div>
      <div class="mt-3 text-center">
        <button class="text-[12px] font-semibold text-fp-700 hover:text-fp-900 underline" @click="pedirPin = !pedirPin">¿Olvidaste tu PIN?</button>
      </div>

      <div v-if="pedirPin" class="mt-3 rounded-xl border border-line bg-paper p-4">
        <div class="text-[13px] font-semibold mb-1.5">Solicitar un PIN nuevo</div>
        <p class="text-[11.5px] text-mut leading-relaxed mb-2.5">Escribe tu cédula. La Comisión de Juntas Electorales y OCLEE te enviará un PIN nuevo por WhatsApp al número que registraste.</p>
        <input v-model="cedPin" class="inp !bg-white" placeholder="000-0000000-0" inputmode="numeric">
        <div class="flex gap-2 mt-2.5">
          <button class="btn-p flex-1" :disabled="pinBusy" @click="solicitarPin">{{ pinBusy ? 'Enviando…' : 'Solicitar' }}</button>
          <button class="btn-o" @click="pedirPin = false; okPin = ''">Cancelar</button>
        </div>
        <div v-if="okPin" class="okbx mt-2.5 text-[12px]">{{ okPin }}</div>
      </div>

      <div class="mt-5 text-center">
        <RouterLink to="/ayuda" class="inline-flex items-center gap-1.5 text-[12px] font-semibold text-fp-700 hover:text-fp-900">ⓘ ¿Cómo funciona mi acceso? · Centro de ayuda</RouterLink>
      </div>

      <div class="mt-9 pt-6 border-t border-line/80">
        <div class="flex items-baseline gap-2">
          <span class="text-[10px] font-bold tracking-[0.28em] text-fp-700 uppercase">Strategos</span>
          <span class="font-serif italic text-[13px] text-mut">στρατηγός</span>
        </div>
        <p class="font-serif text-[13px] leading-relaxed mt-2 text-ink/85">En la Grecia clásica, el <i>strategos</i> era el magistrado electo para conducir la estrategia y la defensa de la ciudad. Bajo ese nombre, la plataforma tecnológica de Fuerza del Pueblo une datos, territorio y organización con un solo propósito: <b>la defensa del voto</b>.</p>
      </div>

      <p class="text-[11px] text-mut/80 text-center mt-7 leading-relaxed">Acceso personal e intransferible.<br>Uso exclusivo institucional · FP 2028 · {{ versionCorta }}</p>
    </div>
  </div>
</template>
