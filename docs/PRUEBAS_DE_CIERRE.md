# Pruebas de Cierre — Portal de Delegados 2028 · v1.6

Sigue este guion en orden. Cada punto trae **los clics exactos** y **el resultado esperado**. Si un punto falla, anota su número y el mensaje — ese dato ubica la causa al instante.

## 0 · Activación (una vez)

1. Supabase → SQL Editor → ejecutar **`fase6_cierre_definitivo.sql`** completo (converge todo, sin importar qué fases corriste antes; re-ejecutarlo es seguro).
2. cPanel → subir y extraer **`portal-delegados-dist.zip`** en `/delegados/`.
3. Abrir el portal → recargar **dos veces** (Safari: Cmd + Option + R).
4. ✅ **Esperado:** el pie de la pantalla de acceso dice **v1.6**. Si no lo dice, sigues en caché — recarga de nuevo.

## 1 · Diagnóstico automático

Entrar como admin → **Mi cuenta → Diagnóstico del sistema → Verificar**.
✅ **Esperado:** 7 líneas en ✓ verde: Regiones · Provincias enlazadas (con los primeros nombres) · Distritos · Cobertura por colegio · Bitácora · Fase 5 · Georreferencia de postulantes. Cualquier ✗ te dice exactamente qué script ejecutar.

## 2 · Filtros territoriales del Inicio

1. Inicio → card **"Avance por municipio"**.
2. **Región** → elegir una (p. ej. Gran Santo Domingo). ✅ La tabla se reduce a esa región y el select de **Provincia** muestra solo sus provincias, con nombre.
3. **Provincia** → elegir una. ✅ La tabla se reduce; la columna **Provincia** de la tabla muestra el nombre (ya no en blanco).
4. **Municipio** → elegir uno. ✅ La tabla queda en ese municipio y abajo aparece el card **"Cobertura por colegio · [municipio]"**.

## 3 · Exterior (OCLEE)

**Ámbito → Exterior (OCLEE)**. ✅ El select de Provincia desaparece, el de municipios lista las OCLEE en orden alfabético, y al elegir una el card de cobertura abre **sin error** (aunque diga "Sin colegios" si esa OCLEE no tiene colegios cargados).

## 4 · Distritos (la unidad que faltaba)

Elegir un municipio **con distritos municipales** (p. ej. uno grande de Santo Domingo o San Cristóbal). En el card de cobertura:
✅ **Esperado:** aparece el selector **"Todos los distritos (N)"**; la tabla se agrupa con bandas verdes por **Distrito** (cabecera y DMs, con subtotal de colegios y completos) y dentro por **Recinto**. Elegir un distrito filtra los chips y la tabla a esa demarcación.

## 5 · Formulario General del Municipio (el consolidado firmable)

En el encabezado del card de cobertura → **"⎙ Formulario general del municipio"**.
✅ **Esperado:** vista previa de impresión con membrete FP en verde, línea Región·Provincia·Municipio, cuadro resumen (meta, registrados, avance, colegios completos), totales de Titulares/Suplentes/Observadores, la relación completa numerada (folio, cédula, nombre, cargo, colegio, **distrito**, teléfono), certificación, 3 firmas y línea "Recibido por la Comisión".

## 6 · Reporte para validación (detalle por colegio)

Mismo card → **"⎙ Reporte para validación"**. ✅ Documento agrupado por recinto, cada colegio con sus hasta 3 personas, casillas ☐ Conforme, huecos "pendiente de postulación", resumen y 3 firmas.

## 7 · Filtro de Provincia en Postulantes (tu caso de SD Este)

Postulantes → filtro **Provincia = Santo Domingo** (la del registro que hiciste).
✅ **Esperado:** tu postulante de Santo Domingo Este aparece. (La fase 6 rellenó la provincia/región de todos los registros existentes y un trigger la guarda automáticamente en cada registro nuevo.)

## 8 · Registro con georreferencia automática

Registrar un postulante de prueba en cualquier municipio → abrir su ficha.
✅ En Postulantes, filtrando por su provincia o su región, aparece de inmediato.

## 9 · Usuarios: WhatsApp, acuse, reset, consulta nacional

1. Usuarios → cualquier fila: ✅ botones **↺** (restablecer PIN) y **📱** (siempre visible; sin teléfono abre WhatsApp para elegir el contacto).
2. Columna **Instructivo**: ✅ ✓ con fecha para quien confirmó la lectura del Protocolo, "Pendiente" en ámbar para quien no.
3. **+ Nuevo usuario** → rol **Consulta Nacional**: ✅ no pide territorio; al entrar con esa cuenta se ve todo el país, puede imprimir, y no tiene Registrar ni validación ni Usuarios.
4. **↺** sobre un usuario territorial: ✅ genera PIN provisional, muestra el mensaje con botón verde de WhatsApp, y el evento queda en **Actividad** como "PIN restablecido".
5. Intentar desactivar **tu propia** cuenta: ✅ el sistema lo bloquea con aviso.

## 10 · Actividad (bitácora total)

Actividad → ✅ se ven accesos, consultas de padrón, registros, ediciones (con los campos cambiados), cambios de etapa y gestión de usuarios; cada fila se expande al detalle antes/después.

## 11 · Impresión con identidad

Cualquier documento → en el diálogo de imprimir activar **"Gráficos de fondo"** y desactivar **"Encabezados y pies de página"**.
✅ El cuadro FP sale **verde**, los membretes completos, y sin la dirección web en los bordes.

## 12 · Ayuda

Menú → **Ayuda** (también visible desde la pantalla de acceso, sin sesión). ✅ Los 3 pasos, roles, instalación en el teléfono, consejos de impresión y el bloque Strategos.

---

**Regla de trabajo desde ahora:** cada entrega incluye su sección de pruebas como esta, punto por punto con resultado esperado, para darla por cerrada al recibirla.
