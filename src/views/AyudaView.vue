<script setup>
import { sesion } from '../stores/auth';
import { reqLbl } from '../lib/constantes';
</script>

<template>
  <div :class="sesion ? '' : 'min-h-screen bg-paper'">
    <div class="max-w-3xl mx-auto px-4 py-6 space-y-4" :class="sesion ? '' : 'pt-10'">

      <div v-if="!sesion" class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2.5">
          <div class="w-8 h-8 rounded-lg bg-fp-600 text-white grid place-items-center font-bold text-[13px]">FP</div>
          <div class="font-serif font-bold text-[15px]">Delegados 2028</div>
        </div>
        <RouterLink to="/acceso" class="btn-o btn-s">← Volver al acceso</RouterLink>
      </div>

      <div>
        <h2 class="font-serif text-xl font-bold">Centro de ayuda</h2>
        <p class="text-[12.5px] text-mut mt-0.5">Todo lo que necesitas saber para entrar y trabajar en el portal, explicado paso a paso y sin tecnicismos.</p>
      </div>

      <!-- Tu acceso en 3 pasos -->
      <div class="card p-5">
        <h3 class="font-serif font-bold text-[15px] mb-4">Tu acceso, en 3 pasos</h3>
        <div class="grid sm:grid-cols-3 gap-3">
          <div class="rounded-xl border border-line bg-paper p-4">
            <div class="w-8 h-8 rounded-full bg-fp-600 text-white grid place-items-center font-serif font-bold text-[15px] mb-2">1</div>
            <div class="font-semibold text-[13px] mb-1">Recibe tu acceso por WhatsApp</div>
            <p class="text-[12px] leading-relaxed text-mut">La Comisión te envía un mensaje con el <b>enlace del portal</b>, tu usuario (tu <b>cédula</b>) y un <b>PIN inicial</b> de 6 dígitos.</p>
          </div>
          <div class="rounded-xl border border-line bg-paper p-4">
            <div class="w-8 h-8 rounded-full bg-fp-600 text-white grid place-items-center font-serif font-bold text-[15px] mb-2">2</div>
            <div class="font-semibold text-[13px] mb-1">Entra con cédula y PIN</div>
            <p class="text-[12px] leading-relaxed text-mut">Abre el enlace, escribe tu cédula (con o sin guiones, da igual) y el PIN del mensaje. Toca <b>Entrar</b>.</p>
          </div>
          <div class="rounded-xl border border-line bg-paper p-4">
            <div class="w-8 h-8 rounded-full bg-fp-600 text-white grid place-items-center font-serif font-bold text-[15px] mb-2">3</div>
            <div class="font-semibold text-[13px] mb-1">Crea tu PIN personal</div>
            <p class="text-[12px] leading-relaxed text-mut">La primera vez, el sistema te pedirá crear <b>tu propio PIN</b> (mínimo 6 caracteres). Desde ese momento, <b>solo tú lo conoces</b>.</p>
          </div>
        </div>
      </div>

      <details class="card acc" open>
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Tu usuario y tu PIN, explicados</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2.5">
          <p><b>Tu usuario es tu cédula.</b> No necesitas correo, ni recordar nombres de usuario: la misma cédula de siempre.</p>
          <p><b>Tu PIN es tu clave personal.</b> El PIN que te llegó por WhatsApp es solo para la primera entrada; el que tú creas después es <b>secreto, personal e intransferible</b>. Queda cifrado de forma que <b>nadie</b> puede verlo — ni la Comisión, ni el administrador, nadie.</p>
          <p class="warn !text-[12.5px]"><b>Nunca compartas tu PIN.</b> Todo lo que se haga con tu usuario queda registrado a tu nombre en la bitácora del sistema. La Comisión <b>jamás</b> te pedirá tu PIN por teléfono ni por mensaje.</p>
          <p><b>¿Olvidaste tu PIN?</b> Comunícate con la Comisión de Juntas Electorales y OCLEE: te generarán uno provisional y el sistema te pedirá crear el tuyo de nuevo al entrar.</p>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Instala la app en tu teléfono</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-3">
          <p>El portal se instala como una aplicación, con su ícono FP en tu pantalla de inicio — sin tiendas ni descargas pesadas.</p>
          <div class="grid sm:grid-cols-2 gap-3">
            <div class="rounded-xl border border-line bg-paper p-3.5">
              <div class="font-semibold text-[12.5px] mb-1.5">En Android</div>
              <p class="text-[12px] text-mut leading-relaxed">Al abrir el portal, toca el botón <b>“Instalar la aplicación”</b> (o en el menú ⋮ del navegador, <b>“Instalar aplicación”</b>). Confirma y listo.</p>
            </div>
            <div class="rounded-xl border border-line bg-paper p-3.5">
              <div class="font-semibold text-[12.5px] mb-1.5">En iPhone</div>
              <p class="text-[12px] text-mut leading-relaxed">Abre el portal en <b>Safari</b> → botón <b>Compartir</b> ⬆︎ → <b>“Agregar a pantalla de inicio”</b> → <b>Agregar</b>.</p>
            </div>
          </div>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Qué puede hacer cada rol</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <div class="rounded-xl border border-fp-100 bg-fp-25 p-3.5">
            <div class="font-semibold text-[12.5px]">✎ Encargado(a) Electoral</div>
            <p class="text-[12px] text-ink/80 mt-0.5">Es quien <b>registra</b> a los postulantes de su territorio en la plataforma, puede editar sus expedientes mientras están en <i>Postulado</i> o <i>Devuelto</i>, e imprime formularios y reportes.</p>
          </div>
          <div class="rounded-xl border border-line bg-paper p-3.5">
            <div class="font-semibold text-[12.5px]">◉ Presidente(a) y Secretario(a) General</div>
            <p class="text-[12px] text-ink/80 mt-0.5"><b>Consultan</b> todo su territorio: el listado de postulantes, la cobertura colegio por colegio, y el <b>Reporte para validación</b> — el documento que revisan, depuran y <b>firman</b> junto al Encargado Electoral. No registran en la plataforma.</p>
          </div>
          <div class="rounded-xl border border-line bg-paper p-3.5">
            <div class="font-semibold text-[12.5px]">◈ Supervisor(a) Provincial y Coordinador(a) Regional</div>
            <p class="text-[12px] text-ink/80 mt-0.5">Dan <b>seguimiento</b> al avance de todos los territorios de su provincia o región: metas, colegios incompletos y listados. No registran.</p>
          </div>
          <div class="rounded-xl border border-line bg-paper p-3.5">
            <div class="font-semibold text-[12.5px]">♟ Administración SNE</div>
            <p class="text-[12px] text-ink/80 mt-0.5">La Comisión valida, devuelve o rechaza postulaciones, gestiona los usuarios y supervisa la bitácora nacional de actividad.</p>
          </div>
          <p class="text-[12px] text-mut">Cada quien ve <b>solo su territorio</b>. Este límite vive en el servidor de datos, no en la pantalla: es una garantía, no una preferencia.</p>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Cómo se registra un postulante</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p>El Encargado Electoral entra a <b>Registrar</b> y sigue 4 pasos: <b>① Cédula</b> — el sistema la busca en el padrón y trae nombre, colegio y recinto de la persona; <b>② Contacto</b> — teléfono, WhatsApp y el cargo al que se postula; <b>③ Requisitos</b> — certifica uno a uno los 7 requisitos del Instructivo; <b>④ Confirmar</b> — revisa y registra. El sistema asigna el <b>número de formulario</b> automáticamente y permite imprimirlo de inmediato para las firmas.</p>
          <p>El sistema verifica solo que la persona <b>vote en la demarcación</b> donde ejercerá y que <b>no esté postulada dos veces</b>. Si detecta que fue <b>delegado(a) en 2024</b>, lo marca como experiencia.</p>
          <p class="text-[12px] text-mut">¿La persona no aparece en el padrón? Existe el <b>registro manual</b>: se capturan sus datos y el expediente queda marcado para que la Comisión lo verifique después.</p>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Consejos al imprimir</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p>Para que los documentos salgan perfectos, en la ventana de impresión del navegador:</p>
          <p>· Activa <b>“Gráficos de fondo”</b> (o “Imprimir fondos”) para que el membrete FP salga en verde.<br>· Desactiva <b>“Encabezados y pies de página”</b> para que no aparezca la dirección web en los bordes de la hoja.<br>· Usa tamaño <b>Carta</b> y márgenes predeterminados.</p>
        </div>
      </details>

      <div class="card p-5">
        <div class="flex items-baseline gap-2">
          <span class="text-[10px] font-bold tracking-[0.28em] text-fp-700 uppercase">Strategos</span>
          <span class="font-serif italic text-[13px] text-mut">στρατηγός</span>
        </div>
        <p class="font-serif text-[13.5px] leading-relaxed mt-2 text-ink/85">En la Grecia clásica, el <i>strategos</i> era el magistrado electo para conducir la estrategia y la defensa de la ciudad: visión, orden y responsabilidad ante su pueblo. Bajo ese nombre, la plataforma tecnológica de Fuerza del Pueblo integra datos, territorio y organización con un solo propósito: <b>la defensa del voto</b>, colegio por colegio.</p>
      </div>

      <p class="text-center text-[11px] text-mut pb-6">Portal de Delegados 2028 · Comisión de Juntas Electorales y OCLEE — SNE·FP</p>
    </div>
  </div>
</template>
