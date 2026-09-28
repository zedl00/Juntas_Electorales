# Seguridad del acceso · cómo funciona (fase 74, 23 de septiembre de 2026)

Todas las capas se activan o desactivan en **Gestión → Configuración → Seguridad del acceso**. Cada cambio queda en Actividad con el nombre de quien lo hizo.

## Capa A · Bloqueo por intentos fallidos

El PIN lo verifica la base de datos en cada intento, a través de un «gancho» que Supabase Auth llama antes de responder. Por eso no se puede evitar llamando a la API directamente ni bloquear a otro a propósito.

| Situación | Qué pasa |
|---|---|
| Fallos 1 y 2 | «Cédula o PIN incorrectos» |
| Fallos 3 y 4 | «PIN incorrecto. Te quedan N intento(s) antes del bloqueo» |
| Fallo 5 | Bloqueo temporal de 15 minutos; queda en Actividad |
| Tras los 15 minutos | Vuelve a tener 5 intentos |
| Vuelve a agotarlos | **Bloqueo definitivo**: solo la administración lo levanta desde Gestión → Usuarios → «Usuarios bloqueados» |
| Acierta | El contador vuelve a cero |

Los tres números (aviso, bloqueo y minutos) son configurables. Un usuario bloqueado no tiene rol para la base de datos: aunque tuviera una sesión abierta, ninguna consulta le responde.

## Capa B · Verificación de identidad con el padrón

En el primer ingreso, antes de crear el PIN personal, la persona escribe su **fecha de nacimiento** y, si la Comisión lo configuró («Fecha de nacimiento y municipio»), el **municipio donde vota**. Por defecto se pide solo la fecha, que es lo más ágil. Se contrastan con el padrón de la Junta. La administración de la SNE nunca pasa por esta verificación (fase 76). Tres fallos: bloqueo definitivo y aviso en «Usuarios bloqueados». Si la cédula no está en el padrón cargado, se deja pasar y queda marcada para la confirmación de la SNE. Quien reciba un PIN por error no conoce esos datos.

Con «Volver a pedirla cada vez que se restablece el PIN» (activado por defecto, fase 79), todo restablecimiento desde Gestión o desde el asistente borra la verificación anterior: la persona la repite en el siguiente ingreso y hasta entonces consulta pero no registra. La confirmación de la SNE no se repite, porque el restablecimiento lo hizo la propia SNE. Cada reinicio queda en Actividad como «identidad_reiniciada».

## Capa C · PIN inicial de un solo uso con caducidad

Todo PIN inicial nace con fecha de vencimiento (72 horas por defecto). Si se intenta usar vencido, el acceso pide uno nuevo. Regenerar un PIN reinicia el plazo. Un PIN viejo filtrado no sirve.

## Capa D · Confirmación de la SNE

Cada primer ingreso queda registrado con fecha, hora y dispositivo, y aparece en Gestión → Usuarios → «Primeros ingresos por confirmar». La administración llama a la persona y confirma o desactiva. Hasta la confirmación, la persona consulta pero **no puede registrar**; lo ve en un aviso amarillo bajo la barra superior.

## Si alguien olvidó su PIN

En la pantalla de acceso, «¿Olvidaste tu PIN?» → cédula → Solicitar. La solicitud cae en Gestión → Usuarios → «Solicitudes de PIN pendientes». La administración pulsa «Restablecer y enviar», se genera un PIN nuevo con su plazo, y se envía por WhatsApp. La respuesta en pantalla es la misma exista o no la cuenta, para no revelar quién es usuario, y solo se admite una solicitud pendiente por cédula.

## Envío de accesos por WhatsApp

Gestión → Usuarios → «Accesos por enviar» lista los PIN iniciales aún no entregados. «Enviar siguiente por WhatsApp» abre WhatsApp con el mensaje completo y, al volver, marca la entrega con nombre y hora. Los PIN vencidos no se envían: se regeneran primero. Cuando Meta habilite el canal automático, la misma bandeja enviará en lote.

## Cómo entra la gente (fase 75)

El plan Pro de Supabase no incluye el gancho de verificación de contraseña, así que el acceso pasa por una **función de servidor** propia («acceso»):

1. Recibe cédula y PIN (y el token del captcha si está activo, que verifica con la clave secreta de Turnstile).
2. Llama a `portal_acceso_verificar`, que comprueba bloqueos, verifica el PIN contra la base y **cuenta los fallos** con las reglas configuradas. Solo el rol de servicio puede llamarla.
3. Si todo está bien, crea la sesión con un enlace de un solo uso y la devuelve al portal.

Para que nadie rodee la función, el gancho **Customize Access Token** (disponible en Pro) niega la sesión a cualquier usuario del portal que entre por contraseña directa o que esté bloqueado. Se aplica también al refrescar sesiones, así que un bloqueo corta sesiones abiertas.

## Puesta en marcha (una sola vez, en el panel de la base de datos)

1. **Desplegar la función «acceso».** Edge Functions → Deploy a new function → nombre `acceso` → pegar el contenido de `supabase/functions/acceso/index.ts` → Deploy. En Edge Functions → Secrets añadir `EMAIL_DOM` = `@strategosfp.com` y, cuando exista el widget de Turnstile, `TURNSTILE_SECRET` con la Secret Key.
2. **Gancho.** Authentication → Auth Hooks → Add hook → **Customize Access Token (JWT) Claims hook** → Postgres → esquema `public` → función `portal_hook_token` → Create hook. Debe quedar Enabled.
3. **Captcha en el panel: apagado.** Authentication → Attack Protection → Captcha protection debe estar desactivado; lo verifica la función.
4. Subir `dist` y probar el acceso. Las sesiones abiertas antes de este cambio tendrán que volver a entrar una vez.
