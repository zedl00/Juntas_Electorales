# API de verificación de membresía · Portal de Delegados 2028

Para la **Secretaría de Organización**. Versión 1 · 1 de octubre de 2026.

## Para qué sirve

El Portal de Delegados registra a las personas postuladas como delegados de juntas. La Secretaría de Organización verifica, con su padrón de miembros, si cada cédula registrada corresponde a un miembro del partido. Este API permite hacerlo sin intercambiar archivos: la Secretaría **retira lotes** de cédulas pendientes y **devuelve** cada cédula con su estado. El portal guarda la respuesta y la muestra en sus listados.

Solo viaja la cédula. No se entregan nombres, teléfonos ni ningún otro dato.

## Dirección y autenticación

- Dirección base: `https://eskdfhjdkcnixkkivjeo.supabase.co/functions/v1/verificacion`
- Cada llamada lleva la clave que emite la Comisión: cabecera `Authorization: Bearer <clave>` (también se acepta `x-api-key: <clave>`).
- Solo HTTPS. La clave se puede revocar y reemplazar en cualquier momento; si la Secretaría sospecha que se filtró, pide una nueva.
- Cada llamada queda registrada: consumidor, dirección IP, hora, cuántos registros se entregaron o recibieron y cuántos se rechazaron.

## 1 · Retirar un lote de cédulas pendientes

```
GET /pendientes?limite=200
```

Arma un lote nuevo con hasta `limite` cédulas registradas que aún no han sido verificadas (por defecto 200; el máximo lo fija la Comisión). Las cédulas entregadas quedan marcadas como «enviadas» y **no vuelven a salir en otro lote**, salvo las que la Secretaría devuelva como `en_revision`.

Respuesta:

```json
{ "ok": true, "lote": 12, "creado_en": "2026-10-01T14:05:11Z", "cantidad": 200,
  "registros": [ { "cedula": "00100000017" }, { "cedula": "00100000025" } ] }
```

Si no hay nada pendiente: `"cantidad": 0` y `"registros": []`.

## 2 · Volver a descargar un lote

```
GET /lotes/12
```

Devuelve el mismo lote con el estado actual de cada cédula. Útil si se perdió la respuesta anterior.

## 3 · Devolver los resultados

```
POST /resultados
Content-Type: application/json

{ "lote": 12,
  "resultados": [
    { "cedula": "00100000017", "estado": "miembro" },
    { "cedula": "00100000025", "estado": "no_miembro", "nota": "renunció en 2024" },
    { "cedula": "00100000033", "estado": "no_localizado" },
    { "cedula": "00100000041", "estado": "en_revision" }
  ] }
```

- `lote` es opcional; si se omite, cada cédula se asocia al lote en que salió.
- Se puede responder un lote completo o por partes, en varias llamadas. Si una cédula se responde dos veces, vale la última.
- Máximo 1000 resultados por llamada.

Respuesta:

```json
{ "ok": true, "recibidos": 4, "aceptados": 3,
  "rechazados": [ { "cedula": "00100000033", "motivo": "no ha sido enviada en ningún lote" } ],
  "lotes": [12] }
```

## Estados

| Estado | Significado |
|---|---|
| `miembro` | La cédula corresponde a un miembro del partido. |
| `no_miembro` | La persona existe en el padrón pero no es miembro. |
| `no_localizado` | La cédula no aparece en el padrón de la Secretaría. |
| `en_revision` | La Secretaría aún lo está verificando. Volverá a salir en un lote futuro. |

Los estados solo se marcan y se reportan; no bloquean ningún registro.

## Validaciones que hace el portal en cada llamada

- Clave vigente y consumidor activo; si la Comisión configuró direcciones permitidas, la IP debe ser una de ellas.
- Cada cédula debe tener 11 dígitos y dígito verificador correcto. Se aceptan con o sin guiones.
- El estado debe ser uno de los cuatro. Se rechaza cualquier otro, con el motivo.
- La cédula debe ser de un postulante registrado y haber salido en algún lote. Lo que no cumple se rechaza línea por línea; el resto se acepta.

## Errores

| Código HTTP | `codigo` | Qué pasó |
|---|---|---|
| 401 | `sin_clave` / `clave_invalida` | Falta la clave, o no es válida o fue revocada. |
| 403 | `ip_no_permitida` | La dirección no está autorizada para este consumidor. |
| 400 | `json_invalido` / `formato_invalido` / `lista_vacia` | El cuerpo no es JSON, no trae `resultados`, o la lista está vacía. |
| 413 | `exceso` | Más de 1000 resultados en una llamada. |
| 404 | `lote_inexistente` / `ruta_desconocida` | El lote no existe, o la ruta no es una de las tres. |

## Ejemplos listos para copiar

```bash
curl -s "https://eskdfhjdkcnixkkivjeo.supabase.co/functions/v1/verificacion/pendientes?limite=200" \
  -H "Authorization: Bearer fp_XXXXXXXX"
```

```bash
curl -s -X POST "https://eskdfhjdkcnixkkivjeo.supabase.co/functions/v1/verificacion/resultados" \
  -H "Authorization: Bearer fp_XXXXXXXX" -H "Content-Type: application/json" \
  -d '{"lote":12,"resultados":[{"cedula":"00100000017","estado":"miembro"},{"cedula":"00100000025","estado":"no_miembro"}]}'
```

## Si la Secretaría prefiere seguir en manual

El circuito es el mismo. La Comisión genera el lote desde el portal y lo entrega como archivo con tres columnas: `cedula, estado, nota`. La Secretaría completa la columna `estado` con uno de los cuatro valores y devuelve el archivo; la Comisión lo carga en el portal. Cada archivo corresponde a un lote y queda registrado igual que una llamada al API.
