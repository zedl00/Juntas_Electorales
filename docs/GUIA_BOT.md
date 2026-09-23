# Bot de Seguimiento — Guía de Puesta en Marcha

**Portal de Delegados 2028 · SNE · Fuerza del Pueblo**

El bot permite consultar desde el celular el avance nacional, por región, provincia, municipio y **distritos** — solo números y porcentajes, **nunca nombres ni datos personales** — y, para los chats de administración, **restablecer PIN de usuarios** al instante. Corre como Edge Function dentro del mismo proyecto Supabase: sin servidores adicionales y sin costo extra.

> ¿Por qué Telegram y no WhatsApp? WhatsApp exige la API de Meta Business (aprobación, número dedicado y costo por conversación). Telegram es gratuito e inmediato, y el flujo de trabajo es idéntico. Si más adelante se quiere WhatsApp, la misma función se adapta — los RPC del bot ya están listos para cualquier canal.

---

## 1 · Crear el bot (2 minutos)

1. En Telegram, abre **@BotFather** → `/newbot`.
2. Nombre sugerido: `Delegados FP 2028` · usuario: `DelegadosFP2028_bot` (debe terminar en `_bot`).
3. BotFather te da el **token** (algo como `7912345678:AAH...`). Guárdalo.

## 2 · Requisito en la base de datos

Ejecutar `sql/fase5_consulta_bot_y_ajustes.sql` en el SQL Editor (si no se ha hecho). Crea la tabla de chats autorizados y las funciones de consulta agregada y reset.

## 3 · Desplegar la función (desde tu Mac)

```bash
brew install supabase/tap/supabase        # una sola vez
cd ~/Proyectos/portal-delegados
supabase login                            # abre el navegador
supabase link --project-ref eskdfhjdkcnixkkivjeo
supabase secrets set TELEGRAM_TOKEN=EL_TOKEN_DE_BOTFATHER
supabase functions deploy telegram-bot --no-verify-jwt
```

## 4 · Conectar Telegram con la función (webhook)

Una sola línea en la Terminal (sustituye `EL_TOKEN` en los dos lugares):

```bash
curl "https://api.telegram.org/botEL_TOKEN/setWebhook?url=https://eskdfhjdkcnixkkivjeo.supabase.co/functions/v1/telegram-bot"
```

Debe responder `{"ok":true,...}`. Listo: el bot está vivo.

## 5 · Autorizar los chats (control total de la Comisión)

Cualquier persona que le escriba al bot recibirá "no autorizado" hasta que la Comisión la habilite:

1. La persona envía **/id** al bot y comparte el número que recibe.
2. En el SQL Editor:

```sql
-- Chat de consulta (dirigente del centro electoral, coordinador, etc.)
insert into delegados.bot_usuarios (chat_id, cedula, descripcion, rol)
values (123456789, '00112345678', 'Coordinador Región Este', 'consulta');

-- Chat de administración (puede además restablecer PIN con /pin)
insert into delegados.bot_usuarios (chat_id, cedula, descripcion, rol)
values (987654321, '01200690764', 'Nestor Valdez · SNE', 'admin');
```

Para revocar un acceso: `update delegados.bot_usuarios set activo = false where chat_id = 123456789;`

## 6 · Comandos

| Comando | Quién | Qué devuelve |
|---|---|---|
| `/avance` | consulta y admin | Nacional: barra de avance, meta, registrados, colegios completos/incompletos/sin registro y desglose por región |
| `/region Este` | consulta y admin | Avance de la región + todas sus provincias |
| `/provincia Santiago` | consulta y admin | Avance de la provincia + todos sus municipios |
| `/municipio Los Alcarrizos` | consulta y admin | Avance del municipio + cobertura de colegios + **sus distritos** (con marca DM) |
| `/pin 00112345678` | solo admin | Restablece el PIN del usuario: genera PIN provisional, obliga a crear PIN personal al entrar, y queda en la bitácora del portal (`reset_pin · método: bot`) |
| `/id`, `/ayuda` | todos | Identificador del chat · lista de comandos |

## Seguridad

- Los RPC del bot solo pueden ejecutarse con la llave de servicio (rol `service_role`): **ningún usuario del portal ni visitante puede invocarlos**.
- La autorización es por chat exacto, gestionada solo por la Comisión, revocable al instante.
- Las consultas devuelven **exclusivamente agregados** (metas, totales, porcentajes, cobertura). Los nombres y cédulas de postulantes jamás salen por este canal.
- El `/pin` rechaza cuentas de administración (esas se gestionan en el sistema SNE) y cada uso queda registrado en la sección Actividad del portal.
