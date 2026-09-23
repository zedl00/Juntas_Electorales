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

En el primer ingreso, antes de crear el PIN personal, la persona escribe su **fecha de nacimiento** y el **municipio donde vota**. Se contrastan con el padrón de la Junta. Tres fallos: bloqueo definitivo y aviso en «Usuarios bloqueados». Si la cédula no está en el padrón cargado, se deja pasar y queda marcada para la confirmación de la SNE. Quien reciba un PIN por error no conoce esos datos.

## Capa C · PIN inicial de un solo uso con caducidad

Todo PIN inicial nace con fecha de vencimiento (72 horas por defecto). Si se intenta usar vencido, el acceso pide uno nuevo. Regenerar un PIN reinicia el plazo. Un PIN viejo filtrado no sirve.

## Capa D · Confirmación de la SNE

Cada primer ingreso queda registrado con fecha, hora y dispositivo, y aparece en Gestión → Usuarios → «Primeros ingresos por confirmar». La administración llama a la persona y confirma o desactiva. Hasta la confirmación, la persona consulta pero **no puede registrar**; lo ve en un aviso amarillo bajo la barra superior.

## Si alguien olvidó su PIN

En la pantalla de acceso, «¿Olvidaste tu PIN?» → cédula → Solicitar. La solicitud cae en Gestión → Usuarios → «Solicitudes de PIN pendientes». La administración pulsa «Restablecer y enviar», se genera un PIN nuevo con su plazo, y se envía por WhatsApp. La respuesta en pantalla es la misma exista o no la cuenta, para no revelar quién es usuario, y solo se admite una solicitud pendiente por cédula.

## Envío de accesos por WhatsApp

Gestión → Usuarios → «Accesos por enviar» lista los PIN iniciales aún no entregados. «Enviar siguiente por WhatsApp» abre WhatsApp con el mensaje completo y, al volver, marca la entrega con nombre y hora. Los PIN vencidos no se envían: se regeneran primero. Cuando Meta habilite el canal automático, la misma bandeja enviará en lote.

## Puesta en marcha (una sola vez, en el panel de la base de datos)

La capa A necesita que Supabase llame al gancho:

1. Panel de la base de datos → **Authentication → Hooks**.
2. **Password Verification Attempt** → Enable → tipo **Postgres** → esquema `public` → función `portal_hook_verificacion_pin` → Save.

Sin ese paso, la fase 74 está aplicada pero los intentos fallidos no se cuentan. Las capas B, C y D funcionan sin él.
