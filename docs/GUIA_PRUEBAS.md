# Guía de Pruebas de Aceptación — Portal de Delegados 2028

**Cómo usarla:** ejecuta cada prueba en orden y marca ✅ PASA o ❌ FALLA. Si algo falla, anota el texto exacto del error o una captura. A partir de esta entrega, cada nueva funcionalidad vendrá con su sección "Cómo probarlo" aquí.

---

## 0 · Activación (obligatorio antes de probar)

1. Supabase → SQL Editor → ejecutar **completo** `fase4_distritos_y_regiones.sql` (versión de hoy).
2. Ejecutar **completo** `fase5_consulta_bot_y_ajustes.sql` (versión de hoy). *El orden importa.*
3. Subir `portal-delegados-dist.zip` a cPanel → carpeta `/delegados/` → Extract (reemplazar).
4. Abrir el portal → recargar **dos veces** (Safari: Cmd + Option + R).
5. **Verificación:** el pie de la pantalla de acceso dice **v1.6**. Si no lo dice, estás viendo caché — repite el paso 4.

## 1 · Diagnóstico automático

Mi cuenta → **Diagnóstico del sistema → Verificar**.
**Esperado:** 6 líneas en ✓ verde: Regiones (con sus nombres), **Provincias enlazadas** (con las primeras 3), Distritos, Cobertura por colegio, Bitácora, Fase 5. *Cualquier ✗ te dice exactamente qué fase re-ejecutar.*

## 2 · Cadena de filtros del Inicio

1. **Ámbito: todos** → la tabla lista todos los municipios; columna **Provincia con nombres** (ya no en blanco).
2. **Región** (ej. Gran Santo Domingo) → el select de Provincia se reduce a las de esa región.
3. **Provincia: Santo Domingo** → el select de Municipio se reduce a los de esa provincia. **Los municipios aparecen** (este era el fallo del padre poblado).
4. Elegir **Santo Domingo Este** → la tabla queda en esa fila y abajo aparece el card **"Cobertura por colegio · Santo Domingo Este"** sin ningún error rojo.
5. **Ámbito: Exterior (OCLEE)** → el select de provincia desaparece; el de municipios lista las OCLEE alfabéticas; al elegir una carga su cobertura **sin** el error "structure of query…". Si una OCLEE no tiene colegios mapeados, mostrará "Sin colegios para este municipio" — eso es correcto, no es error.

## 3 · Distritos (el detalle que faltaba ver)

En el card de cobertura de un municipio **con distritos** (Santo Domingo Este, Santiago, Los Alcarrizos…):
**Esperado:** un selector **"Todos los distritos (N)"** en el encabezado del card; la tabla agrupada con **franjas verdes por distrito** (cabecera y cada DM con su subtotal de colegios) y dentro, por recinto. Elegir un distrito filtra chips y tabla a esa demarcación. *Si un municipio no tiene DM, el selector no aparece: correcto.*

## 4 · Formularios imprimibles (dónde están)

En el mismo card de cobertura, dos botones arriba a la derecha:
- **⎙ Formulario general del municipio** → hoja con membrete FP verde, Región·Provincia·Municipio, cuadro resumen (meta, registrados, avance, colegios completos), totales de los 3 cargos, la **relación completa numerada** (folio, cédula, nombre, cargo, colegio, **distrito**, teléfono) y las 3 firmas + línea "Recibido por la Comisión".
- **⎙ Reporte para validación** → detalle recinto→colegio con 3 renglones por colegio y casillas ☐ Conforme.
**Al imprimir:** activar "Gráficos de fondo" (logo verde) y desactivar "Encabezados y pies" (quita la URL del navegador).

## 5 · Consulta de postulantes (tu caso de Santo Domingo Este)

1. Postulantes → filtro **Provincia: Santo Domingo** → **Esperado:** aparece tu postulante registrado en Santo Domingo Este (la fase 4 de hoy rellenó la provincia en los expedientes ya guardados; los nuevos la heredan solos).
2. Filtro **Municipio: Santo Domingo Este** → mismo resultado.
3. Abrir el expediente → se ve **Correo · Vínculo FP**; botón Editar permite cambiar el vínculo (Militante/Miembro/Simpatizante).

## 6 · Registro (incluye manual)

1. Registrar → cédula real del padrón → Verificar → datos completos → en Contacto están **Correo** y **Vínculo con el partido** → completar 4 pasos → folio asignado → imprimir individual: la hoja muestra Región/Provincia/Municipio/Circunscripción, Correo y Vínculo.
2. Cédula inexistente (ej. 00000000009) → botón **"¿No aparece? Registrar manualmente"** → formulario ámbar → registra con la marca "[Registro manual…]" visible en notas.

## 7 · Usuarios y accesos

1. Usuarios → **+ Nuevo usuario** → cédula de prueba 11 dígitos → rol **Encargado(a) Electoral** + un municipio → Crear → **Esperado:** mensaje con "▸ PIN inicial: XXXXXX" y **botón verde "📱 Enviar por WhatsApp"** (con teléfono abre el chat directo; sin teléfono abre WhatsApp para elegir contacto).
2. En la fila del usuario: botones **↺** (restablecer PIN → genera provisional + mensaje con PIN + WhatsApp; el evento queda en Actividad) y **📱** (reenviar acceso).
3. Columna **Instructivo**: "Pendiente" en ámbar; cuando el usuario confirme la lectura en Protocolo, cambia a ✓ con fecha.
4. Crear un usuario rol **Consulta Nacional** (no pide territorio) → entrar con él → ve todo el país, imprime formularios, **no** puede registrar ni validar ni ver Usuarios/Actividad.
5. Intentar desactivar **tu propia cuenta** → el sistema lo bloquea con aviso.

## 8 · Actividad y Ayuda

- Actividad (admin): aparecen accesos, consultas de padrón, el registro de la prueba 6, el reset de la 7.2 ("PIN restablecido"), con detalle expandible antes/después.
- Ayuda: visible en el menú para todos y **desde la pantalla de acceso sin sesión** ("ⓘ ¿Cómo funciona mi acceso?").

## 9 · Bot (opcional, cuando instales el Telegram oficial — gratis, desarrollador Telegram FZ-LLC)

Seguir `GUIA_BOT.md`. Prueba mínima: `/id` → autorizar el chat → `/avance` devuelve la barra nacional; `/municipio Santo Domingo Este` devuelve avance + cobertura + **distritos**.

---

**Regla de cierre:** una entrega se da por cerrada cuando todas sus pruebas marcan ✅. Lo que marque ❌ se reporta con el texto del error y se corrige antes de avanzar.
