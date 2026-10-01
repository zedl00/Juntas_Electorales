<script setup>
import { sesion, esAdmin } from '../stores/auth';
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
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Tu primer ingreso, paso a paso</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p><b>1 · Entra con tu cédula y el PIN inicial</b> que recibiste por WhatsApp. Ese PIN es de un solo uso y vence a los tres días; si venció, pide otro con «¿Olvidaste tu PIN?».</p>
          <p><b>2 · Confirma que eres tú.</b> El sistema te pide tu fecha de nacimiento (y, si la Comisión lo configuró, el municipio donde votas) y la compara con el padrón de la Junta. Tienes tres intentos; si no coinciden, el acceso se bloquea y solo la Comisión lo habilita. Si no tienes los datos a mano, «Verificar más tarde» te deja entrar solo a consultar.</p>
          <p><b>3 · Crea tu PIN personal.</b> Mínimo 6 caracteres. Desde ese momento solo tú lo conoces.</p>
          <p><b>4 · La Comisión confirma tu acceso.</b> Verás un aviso amarillo mientras tanto: puedes consultar, y podrás registrar cuando la SNE confirme tu identidad, normalmente el mismo día.</p>
          <p class="text-[12px] text-mut"><b>Si te equivocas de PIN:</b> a partir del tercer fallo el sistema te dice cuántos intentos te quedan; al quinto bloquea el acceso 15 minutos. Si vuelve a pasar, el bloqueo es definitivo y lo levanta la Comisión desde Gestión → Accesos y seguridad.</p>
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
          <p>El sistema comprueba que la persona <b>no esté postulada dos veces</b> y dónde <b>vota</b> según el padrón. Si detecta que fue <b>delegado(a) en 2024</b>, lo marca como experiencia.</p>
          <p><b>Dónde vota y dónde trabajará son dos cosas distintas.</b> Dónde vota lo dice la Junta y no cambia. Dónde trabajará lo decide el partido: si la persona vota en el municipio, queda en su propio colegio sin preguntar; la Comisión puede configurar que se pregunte el colegio en cada registro para repartir gente entre recintos. <b>Solo el colegio donde trabajará cuenta para la cobertura</b>: un colegio está cubierto con tres personas asignadas.</p>
          <p><b>El Encargado Electoral registra solo a quien vota en su municipio.</b> Si la cédula vota en otro municipio, el sistema lo avisa y no permite continuar. Registrar a alguien que vota fuera es tarea de la administración de la SNE, y depende de la configuración de traslados.</p>
          <p class="text-[12px] text-mut">¿La persona no aparece en el padrón? Existe el <b>registro manual</b>: se capturan sus datos y el expediente queda marcado para que la Comisión lo verifique después.</p>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Avance: seguimiento por territorio</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p><b>Qué es.</b> La pantalla de seguimiento con cifras, sin nombres de personas. Cada quien entra en su nivel: la SNE ve regiones, un coordinador sus provincias, la dirigencia provincial sus municipios y un encargado municipal sus distritos y colegios.</p>
          <p><b>Cómo se lee.</b> En cada fila: colegios, meta (3 por colegio), registrados y porcentaje, <b>colegios ✓</b> (con 3 o más personas), <b>incompletos</b> (parciales con 1 o 2, más vacíos sin nadie) y <b>faltan</b> (personas que hacen falta para completar la meta). Las filas se ordenan de menor a mayor avance para ver primero dónde empujar; también por más faltantes o por nombre, y con «Solo incompletos».</p>
          <p><b>Bajar de nivel.</b> Toca una fila para entrar: región › provincia › municipio › distrito › colegios. En el último nivel se ve cada colegio con cuántas personas tiene y cuántas le faltan. La ruta de arriba permite volver.</p>
        </div>
      </details>

      <details class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Asignación de colegios</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p>La pantalla <b>Asignación</b> es la herramienta de ajuste; en el registro diario casi no hace falta. Sirve para: dar colegio a quien quedó sin él (registros anteriores o traslados aprobados después), <b>mover</b> a alguien a otro colegio del mismo municipio cuando uno se llena y otro está vacío, ver quién está <b>reubicado</b> (trabaja en un colegio distinto del que le toca por el padrón), y ver los <b>colegios con faltantes</b>.</p>
          <p>Las cuatro tarjetas de arriba llevan a su lista. Junto a «Asignación» en el menú aparece cuántas personas esperan colegio. Puede asignar y mover la administración de la SNE en todo el país, y en su municipio el Encargado Electoral o quien tenga permiso de registrar. Cada asignación queda en la bitácora.</p>
        </div>
      </details>

      <details v-if="esAdmin" class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Verificación de miembros con la Secretaría de Organización</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p><b>Qué es.</b> La Secretaría de Organización confirma, con su padrón, si cada postulante registrado es miembro del partido. El portal arma <b>lotes</b> de cédulas pendientes (200 por defecto), la Secretaría devuelve cada cédula con su estado, y el portal lo guarda y lo muestra en Postulantes con la columna «Miembro» y su filtro.</p>
          <p><b>Estados.</b> <b>Miembro</b>, <b>No miembro</b> (existe pero no es miembro), <b>No localizado</b> (no está en su padrón) y <b>En revisión</b> (vuelve a salir en un lote futuro). Antes de eso: «Sin verificar» y «Enviado a Organización». Los estados solo se marcan y se reportan; no bloquean el registro ni la impresión.</p>
          <p><b>Dos caminos, un circuito.</b> Por <b>API</b>: la Secretaría retira lotes y devuelve resultados con una clave propia que se crea y revoca en Gestión → Verificación de miembros; cada llamada queda en la bitácora. Por <b>archivo</b>: «Generar lote manual» descarga un CSV con las cédulas; la Secretaría completa la columna estado y la administración lo carga con «Cargar respuesta». Cada archivo es un lote igual que una llamada.</p>
          <p><b>Validaciones.</b> Cédula con dígito verificador correcto, estado permitido, y que la cédula haya salido en un lote. Lo que no cumple se rechaza con su motivo, línea por línea; el resto se carga.</p>
        </div>
      </details>

      <details v-if="esAdmin" class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Accesos y seguridad: qué es cada bandeja y cuándo se usa</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-3">
          <p class="text-[12px] text-mut">Gestión → Accesos y seguridad. Cuatro bandejas independientes. Cada una aparece con su contador; si está en cero, no hay nada que hacer.</p>

          <div class="rounded-xl border border-line bg-paper p-3 space-y-1">
            <p><b>Accesos por enviar.</b></p>
            <p><b>Cuándo:</b> cada vez que se crea un acceso, individual o masivo desde el archivo de plenos, o se genera un PIN nuevo. <b>Por dónde:</b> Gestión → Usuarios → «+ Nuevo usuario» o «↺ PIN nuevo». <b>Qué hacer:</b> «Enviar siguiente por WhatsApp» abre WhatsApp con el mensaje completo; al volver, la entrega queda marcada con tu nombre y la hora. Los PIN vencen a las 72 horas: si uno aparece «vencido», genera otro antes de enviarlo.</p>
          </div>

          <div class="rounded-xl border border-line bg-paper p-3 space-y-1">
            <p><b>Solicitudes de PIN pendientes.</b></p>
            <p><b>Cuándo:</b> alguien olvidó su PIN y lo pidió desde la pantalla de acceso con «¿Olvidaste tu PIN?». <b>Por dónde:</b> la pantalla de acceso, sin sesión; solo se admite una solicitud pendiente por cédula y la respuesta es la misma exista o no la cuenta. <b>Qué hacer:</b> «Restablecer y enviar» genera un PIN nuevo, cierra la solicitud y abre WhatsApp para enviarlo. Antes de enviarlo, conviene confirmar por teléfono que quien pide es quien dice ser.</p>
          </div>

          <div class="rounded-xl border border-line bg-paper p-3 space-y-1">
            <p><b>Usuarios bloqueados.</b></p>
            <p><b>Cuándo:</b> por tres caminos. Cinco PIN incorrectos seguidos: bloqueo de 15 minutos, que se levanta solo. Si vuelve a agotar los cinco intentos: bloqueo definitivo. O tres fallos en la verificación de identidad con el padrón: bloqueo definitivo. <b>Por dónde:</b> la pantalla de acceso y la modal «Confirma que eres tú». <b>Qué hacer:</b> llama a la persona; si es quien debe ser, «Habilitar» pone los intentos en cero y levanta el bloqueo. Con el ⓘ junto a su nombre ves su fecha de nacimiento y municipio del padrón para guiarla. Si no la reconoces, déjala bloqueada o desactívala desde Usuarios. Cada bloqueo y cada habilitación quedan en Actividad.</p>
          </div>

          <div class="rounded-xl border border-line bg-paper p-3 space-y-1">
            <p><b>Primeros ingresos por confirmar.</b></p>
            <p><b>Cuándo:</b> la primera vez que una persona entra al portal. Queda registrada la fecha, la hora y el dispositivo. <b>Por dónde:</b> automático, al primer ingreso. <b>Qué hacer:</b> llama a la persona y confirma que es quien debe ser; «Confirmar identidad» la habilita para registrar. Mientras tanto puede consultar pero no registrar, y ve un aviso amarillo. Si no la reconoces, «Desactivar» cierra su acceso con un motivo. La línea «✓ Verificó su identidad con el padrón» te dice si ya pasó la verificación automática.</p>
          </div>

          <p class="text-[12px] text-mut">Orden recomendado cada mañana: bloqueados, primeros ingresos, solicitudes de PIN, accesos por enviar. Los interruptores de cada capa están en Configuración → Seguridad del acceso.</p>
        </div>
      </details>

      <details v-if="sesion" class="card acc">
        <summary class="p-4 flex items-center gap-2 font-serif font-bold text-[15px]"><span class="acc-ic text-fp-600">▸</span> Configuración de la Comisión (Gestión → Configuración)</summary>
        <div class="px-4 pb-4 text-[13px] leading-relaxed space-y-2">
          <p><b>Traslados y asignación de colegio.</b> Tres decisiones: <b>hasta dónde</b> puede moverse una persona respecto al colegio donde vota (su colegio, su municipio, su provincia o libre); <b>qué pasa cuando un registro excede ese alcance</b> (permitir sin trámite, requerir autorización de la SNE, o bloquear); y si <b>los Encargados Electorales solo registran a quien vota en su municipio</b>, que es lo recomendado. También se decide cuándo se pregunta el colegio de trabajo: nunca, solo si la persona vota fuera, o en cada registro.</p>
          <p><b>Autorización de la SNE.</b> Cuando un registro queda pendiente, la persona tiene colegio solicitado pero <b>no cuenta</b> para la cobertura. La administración lo aprueba o rechaza en <b>Dirigencia → Traslados</b>. Al aprobar, el colegio pasa a asignado y la persona empieza a contar. Si se rechaza, queda sin colegio en ese territorio.</p>
          <p><b>Seguridad del acceso.</b> Cuatro capas, cada una con su interruptor: captcha anti-robots en la entrada; <b>bloqueo por intentos fallidos</b> (aviso, bloqueo temporal, y definitivo si se repite, con lista de bloqueados para habilitar); <b>verificación de identidad con el padrón</b> en el primer acceso (fecha de nacimiento, y municipio si se configura; tres intentos), que puede volver a pedirse cada vez que se restablece un PIN; <b>PIN inicial con caducidad</b>; y <b>confirmación de la SNE</b> tras el primer ingreso, sin la cual la persona consulta pero no registra.</p>
          <p><b>Si alguien olvidó su PIN.</b> En la pantalla de acceso, «¿Olvidaste tu PIN?». La solicitud llega a Gestión → Usuarios, la administración genera un PIN nuevo y lo envía por WhatsApp desde «Accesos por enviar».</p>
          <p><b>Quién ve nombres.</b> Nadie ve listados de personas salvo la administración o quien tenga marcada la casilla <b>«Puede ver postulantes»</b> en su usuario (Gestión → Usuarios → Editar). Sin ella, la persona ve solo cifras en <b>Avance</b> y lo que ella misma registró; Postulantes y Asignación no aparecen en su menú. Es una decisión consciente por usuario, de cualquier rol.</p>
          <p><b>Marca de agua y permisos por rol.</b> Qué documentos llevan marca de agua al imprimirse, y qué ve y qué imprime cada rol.</p>
          <p class="text-[12px] text-mut">Todo cambio de configuración queda registrado en Actividad con el nombre de quien lo hizo.</p>
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
