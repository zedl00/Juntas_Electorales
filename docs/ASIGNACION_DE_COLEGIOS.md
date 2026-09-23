# Asignación de colegios · cómo funciona y qué casos cubre

Documento de referencia para la Comisión. Estado al 23 de septiembre de 2026 (v8.7.0).

## 1. Dos territorios por persona

Cada postulante tiene dos lugares distintos, y el sistema los guarda por separado:

| Concepto | Campo | Quién lo decide | Cambia |
|---|---|---|---|
| **Dónde vota** | `id_colegio_padron`, `municipio_padron_id` | La Junta Central Electoral (padrón) | Nunca |
| **Dónde trabajará** | `colegio_asignado`, `municipio_id` | El partido, al registrar o al asignar | Sí |

**Solo el colegio donde trabajará cuenta para la cobertura.** Un colegio está cubierto cuando tiene tres personas asignadas. El colegio donde vota es un dato de referencia y aparece en el formulario impreso, pero no suma en ninguna tarjeta.

## 2. Las dos reglas, que son distintas

**Regla A · Alcance del traslado (parametrizable).** Hasta dónde puede alejarse una persona del colegio donde vota. Se configura en Gestión → Usuarios → Traslados entre demarcaciones, con cuatro niveles: solo su colegio, su municipio, su provincia, libre. Además se decide si lo que exceda requiere autorización de la SNE. Esto es lo que antes estaba en «provincia».

**Regla B · Territorio del colegio de trabajo (fija).** El colegio asignado debe pertenecer al municipio donde se registró a la persona. No es configurable, y no conviene que lo sea: el encargado de un municipio registra gente para cubrir los colegios de su municipio, y el desplegable solo ofrece esos colegios. La función `portal_reasignar_colegio` lo verifica en la base.

Las dos reglas se combinan así: la Regla A decide **si** una persona que vota en un sitio puede registrarse en otro; la Regla B decide **qué colegios** puede recibir una vez registrada.

## 3. El caso de Camilo Moreta Roa (0129-00001)

- Vota en San Juan de la Maguana, colegio 0159.
- Fue registrado por el encargado de Juan de Herrera, un municipio distinto de la misma provincia.
- Se registró antes de la v8.6, cuando el campo «colegio asignado» no existía.

¿Por qué no tiene colegio? Porque su colegio del padrón está en San Juan de la Maguana, y por la Regla B no puede trabajar ahí: lo registró Juan de Herrera para cubrir Juan de Herrera. El sistema no puede adivinar en cuál de los colegios de Juan de Herrera lo quieren, así que lo deja «esperando asignación». Antes de la v8.6 estas personas no contaban en ningún sitio; ahora aparecen en la pantalla Asignación para que alguien les dé colegio.

Si se hubiera registrado hoy, con la configuración actual (alcance provincia, sin autorización), el registro le habría pedido elegir el colegio de Juan de Herrera en el mismo momento y no habría llegado a Asignación.

## 4. Matriz de casos

Con la configuración actual: alcance «provincia», sin autorización obligatoria.

| Caso | Vota en | Se registra en | Regla A | Qué pasa al registrar | Colegio de trabajo |
|---|---|---|---|---|---|
| 1 | Colegio X del municipio M | M | Mismo colegio | Registro normal | X, automático |
| 2 | Colegio X del municipio M | M, pero conviene otro colegio | Mismo municipio | Registro normal | X automático; se cambia luego en Asignación |
| 3 | Municipio M | Municipio N, misma provincia | Misma provincia: permitido | Hoy: **solo el administrador** puede registrarlo (ver §6) | Elegido en el registro entre los colegios de N |
| 4 | Municipio M | Municipio N, otra provincia | Otra provincia: excede | Hoy: solo el administrador; queda «permitido» porque no se exige autorización | Elegido entre los colegios de N |
| 5 | Igual que 4, con autorización obligatoria activada | | Excede | Queda con traslado «pendiente» y aparece en Dirigencia → Traslados para aprobar o rechazar | Elegido entre los colegios de N |
| 6 | Cualquiera | Oficina OCLEE del exterior | No aplica | Registro normal, sin verificación de demarcación | Colegio de la OCLEE |
| 7 | No aparece en el padrón | Cualquiera | No aplica | Registro manual, pendiente de verificación | Elegido en el registro |
| 8 | Registrado antes de la v8.6 fuera de su municipio | | | Sin colegio | Se asigna en la pantalla Asignación |

## 5. Dónde se aplica cada regla hoy

| Control | Pantalla | Función de la base | Base de datos (trigger o política) |
|---|---|---|---|
| Colegio de trabajo dentro del municipio de registro | Sí, el desplegable solo lista esos colegios | Sí, en `portal_reasignar_colegio` | **No** en el registro inicial: el cliente puede enviar cualquier `colegio_asignado` |
| Alcance del traslado | Sí, calcula nivel y estado | Sí, en `portal_evaluar_traslado` | **No**: el cliente envía `traslado_nivel` y `traslado_estado`; la base los acepta |
| Solo el administrador registra fuera del municipio | Sí | No | No |
| Aprobación de traslados pendientes | Dirigencia → Traslados | Sí, `portal_traslado_resolver` | Sí, solo admin |
| Persona pendiente de autorización no debería contar | **No**: cuenta desde que tiene colegio asignado | | |

## 6. Hallazgo: la Regla A hoy es solo informativa

En la pantalla de registro, un encargado que busca una cédula que vota en otro municipio recibe «No pertenece a esta demarcación» y no puede continuar, **sin importar** el alcance configurado. Solo el administrador ve la casilla «Registrar de todos modos». El alcance configurado solo cambia el estado que se guarda y el mensaje. Es decir, la configuración «provincia» promete traslados entre municipios sin trámite, pero el encargado no puede hacerlos.

## 7. Opciones para fortalecer, a decidir por la Comisión

**Opción 1 · Que la Regla A mande de verdad (recomendada).**
Si el traslado está dentro del alcance, cualquier usuario con permiso de registro puede registrar a la persona, eligiendo obligatoriamente el colegio de trabajo. Si excede el alcance y no se exige autorización, también. Si excede y se exige autorización, el registro se guarda como «pendiente», no cuenta para la cobertura hasta que la SNE lo apruebe, y aparece en Dirigencia → Traslados. El administrador conserva su capacidad de registrar cualquier caso.

**Opción 2 · Mantener el bloqueo actual.**
Solo el administrador registra fuera del municipio. La configuración de alcance se reduce a clasificar los casos que el administrador aprueba. Más restrictivo; concentra ese trabajo en la SNE.

**En cualquiera de las dos, hace falta la fase 63:** un disparador en `postulantes_2028` que en la base, y no en la pantalla, verifique que el colegio asignado pertenece al municipio de registro, calcule el nivel y el estado del traslado con `portal_evaluar_traslado`, rechace lo que la configuración no permita, y proteja `traslado_estado`, `autorizado_por` y los datos del padrón para que nadie que no sea administrador los cambie. Sin eso, todo lo anterior se puede saltar llamando a la API directamente.

**Mejoras de la pantalla Asignación, independientes de la decisión:**

- Reasignar a quien ya tiene colegio (mover gente entre colegios del mismo municipio).
- Preseleccionar el colegio del propio recinto de la persona cuando le faltan personas.
- Contador de «esperan colegio» junto a Asignación en el menú.
- Que una persona con traslado «pendiente» se vea marcada y no cuente hasta la aprobación.

## 8. Decisión y aplicación (23 de septiembre de 2026)

La Comisión eligió la **Opción 1** y las cuatro mejoras de pantalla. Se aplicó así:

**Fase 63 (base de datos).**
- Disparador `aa_p28_control_colegio` en `postulantes_2028`, que corre antes que los demás: toma los datos del padrón de la Junta al insertar, calcula nivel y estado del traslado con la configuración vigente, asigna el colegio del padrón automáticamente cuando la persona vota en el mismo municipio, verifica que el colegio de trabajo pertenece al municipio de registro, y bloquea a quien no es administrador el cambio de cédula, territorio, datos del padrón, traslado, sellos y auditoría.
- Un traslado **pendiente** guarda el colegio elegido en `colegio_solicitado` y deja `colegio_asignado` vacío: la persona **no cuenta** para la cobertura hasta que la SNE apruebe. Al aprobar en Dirigencia → Traslados, el colegio solicitado pasa a asignado y `autorizado_por` recibe el nombre de quien aprobó. Al rechazar, la persona queda sin colegio y nadie salvo la administración puede asignarle uno en ese territorio.
- `autorizado_por` ya no lleva el nombre de quien registra: queda vacío hasta la aprobación.
- El distrito (`jce_id`) es el del colegio donde trabajará, no el del padrón.

**Pantalla de registro.** Cualquier usuario con permiso de registro puede registrar a quien vota en otro municipio. El aviso sigue apareciendo, con la casilla de constancia y el colegio obligatorio. Si excede el alcance con autorización exigida, el aviso dice que quedará pendiente.

**Pantalla Asignación.**
- «Esperan colegio»: el colegio con más faltantes viene preseleccionado; el encargado confirma o cambia.
- «Con colegio»: lista de asignados del municipio con opción de moverlos a otro colegio del mismo municipio.
- «Esperan autorización de la SNE»: los traslados pendientes, con el colegio solicitado y acceso directo a la bandeja para el administrador.
- El menú lateral muestra junto a «Asignación» cuántas personas esperan colegio.

**Casos 3 y 4 de la matriz** pasan a: cualquier encargado con permiso puede registrarlos eligiendo colegio. **Caso 5**: queda pendiente y no cuenta hasta aprobarse.

## 9. Ajuste del 23 de septiembre de 2026: el límite del encargado es su municipio

Las juntas electorales, los encargados y el registro son por municipio. Por eso se ajusta la Opción 1:

- **Encargado electoral:** solo registra a quien vota en su propio municipio. Si la cédula vota en otro municipio, la pantalla lo bloquea con un mensaje y la base rechaza el registro aunque se intente por la API (fase 64).
- **Administración de la SNE:** puede registrar a quien vota fuera. Para ella aplica la configuración de alcance y autorización. La opción «provincia» sigue existiendo en la configuración, pero solo la usa la administración.
- Las mejoras de Asignación no cambian.

Casos 3 y 4 de la matriz pasan a: solo la administración. Caso 5: solo la administración, y queda pendiente hasta aprobarse.

## 10. Ajustes del 23 de septiembre de 2026 (fase 67)

- **Qué pasa cuando un registro excede el alcance** pasa a tener tres opciones en Gestión → Usuarios → Traslados: permitir sin trámite, requerir autorización de la SNE, o **bloquear** con el mensaje «Está registrando fuera de su municipio/provincia. La persona debe registrarse en su mismo territorio». El bloqueo se aplica en la pantalla y en la base.
- **El límite del encargado** (solo registra a quien vota en su municipio) es ahora un parámetro visible, activado por defecto.
- **Quién asigna y mueve colegio:** la administración de la SNE en todo el país; en su municipio, el encargado electoral o quien tenga permiso de registrar. Antes cualquier usuario con sesión podía hacerlo.
- **Pantalla Asignación:** las cuatro tarjetas llevan a su lista. «Con colegio» y «Reubicados» se ven también en la vista nacional, con un botón para entrar al municipio y mover. Los reubicados son quienes trabajan en un colegio distinto del que les toca por el padrón.
- **Colegio dentro del mismo municipio:** con «Preguntar en cada registro» el selector aparece también para quien vota en el municipio, con su propio colegio preseleccionado.

## 11. Traslado rechazado (fase 72)

Cuando la SNE rechaza un traslado, la persona sigue registrada con su número de formulario, pero sin colegio: no cuenta para la cobertura, no aparece en «Esperan colegio» y nadie salvo la administración puede darle colegio en ese territorio. Se ve en tres sitios: Dirigencia → Traslados con el filtro «Rechazados», la pantalla Asignación en el bloque «Traslados rechazados por la SNE», y Postulantes en su ficha. Como la cédula solo puede registrarse una vez, la única salida es que la administración **reabra** el caso desde Asignación: vuelve a «pendiente» y entra otra vez en la bandeja para decidirlo de nuevo. Cada reapertura queda en la bitácora.

## 12. Quien vota en el exterior (fase 73)

El padrón marca con «E» a 863,785 personas que votan en el exterior. Para ellas el colegio que trae el padrón es su colegio de **origen** en el país, no su mesa real. Por eso no pueden registrarse en un municipio del país: contarían en un colegio en el que no votan. Solo una oficina OCLEE puede registrarlas. La pantalla lo avisa con «Vota en el exterior» y la base rechaza el registro.
