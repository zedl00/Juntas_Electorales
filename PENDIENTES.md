# Pendientes · Portal de Delegados 2028

Lista viva. Se actualiza en cada sesión de trabajo. Lo primero de «Próximo» es lo que sigue.

## Próximo

0. **Análisis Electoral · pantallas sobre el cruce** (pedido 30 sep): (1) control de cada junta: presidencia y mayoría de titulares por partido, con filtros; (2) reporte para impugnaciones (plazo ~14 oct): juntas sin titular FP y cargos en manos de «Desconocido»; (3) pantalla para clasificar 182 «Desconocido» + 70 fuera de la base, con cédula; (4) mayo frente a resolución (vista_cambios_mayo_2026); (5) exportar la vista a Excel.
0a. **Registro de encargados provinciales**: decidir A (registra eligiendo municipio de su provincia, fase 84) o B (no registra; ocultar Registrar y bloquear la casilla). Hoy el botón Registrar no hace nada para Manuel.
0. **Cerrar la prueba de la fase 82 con Manuel**: (a) registrar una persona de prueba y confirmar que aparece el número de formulario; (b) marcarle «Puede ver postulantes» en Editar usuario, recargar su sesión y confirmar que Postulantes vuelve; luego desmarcar.
0a. **Confirmar la limpieza** de 01200938577 y 07100236442 («2 rows affected» o menos si ya no existían).
3. **Crear un usuario encargado de prueba** en Gestión → Usuarios y verificar el bloqueo: al buscar una cédula de otro municipio debe ver «Vota en otro municipio» sin poder continuar.
4. **Cloudflare, Parte 2**: crear cuenta, importar DNS, cambiar nameservers en GoDaddy. Avisar «activo».

Nota de trabajo: los commits los hace Claude; el `push` lo hace Nestor desde GitHub Desktop después de cada sesión.

## En curso

- **Seguridad de base** (fases 58, 59, 59b, 60 aplicadas). Falta: desactivar registro público en Supabase Auth y activar captcha en Supabase cuando exista el widget de Turnstile (Cloudflare Parte 4).
- **Guardar en el repositorio una copia de las funciones que hoy viven en la base** (las fases 29 a 57 se perdieron como archivos, pero las funciones siguen en Supabase). Cómo: en el editor SQL, correr la consulta de `string_agg(pg_get_functiondef…)`, y en el panel de resultados usar «Export» → «Download CSV»; el archivo cae en Descargas. Decirle a Claude el nombre del archivo y él lo convierte en migración. No es urgente.

## Pendiente

- **Encargados provinciales que registran** (decisión 27 sep: NO por ahora). Hallazgo: un encargado con provincia y sin municipio, aunque tenga «puede registrar», solo ve «Su propio colegio» y la base rechaza el registro (la política exige municipio). Propuesta guardada: selector de municipio limitado a su provincia, política de inserción que acepte municipio dentro de su provincia, y aviso en Editar usuario. Mientras tanto: no dar «puede registrar» a usuarios sin municipio.
- **Lista de usuarios más compacta** (pedido 23 sep): instructivo y estado como iconos con tooltip (fecha o «pendiente» al pasar el ratón); acciones editar, PIN nuevo, reenviar y copiar como iconos con tooltip; filas más cortas.
- **Poner la API detrás del dominio propio** (pedido 23 sep): un Worker de Cloudflare en `api.juntas.strategosfp.com` que reenvíe a Supabase, para que el WAF y los límites de Cloudflare protejan también la API y el proyecto no quede a la vista. Va como Cloudflare Parte 3, después de que la zona esté activa. Un API Gateway autogestionado (Kong, Tyk, APISIX) haría lo mismo pero exige un servidor propio y mantenimiento; no conviene con el equipo actual.

- **Fase 63 · control formal del colegio en el registro** (depende de la decisión del punto 1 de Próximo; hallazgo: hoy el alcance configurado es solo informativo, el encargado nunca puede registrar fuera de su municipio): disparador `before insert/update` en `postulantes_2028` que verifique que `colegio_asignado` pertenece al municipio, recalcule los datos del padrón en la base y proteja `traslado_estado`, `autorizado_por` y columnas sensibles para quien no sea admin.
- **Fase 64 · función definer para Strategos** (`padron_buscar`, `padron_resumen_municipio`, `padron_por_cedula`) y retirar de nuevo el `select` de `jce_padron` a `authenticated`.
- **Listado de Postulantes** no muestra el colegio asignado.
- **Sesión en el navegador**: decidir memoria pura (documento de seguridad) o persistencia con caducidad por inactividad.
- **PIN personal de 8 o más caracteres** (hoy el mínimo es 6).
- **Documentos de seguridad**: corregir la columna «Estado» (Cloudflare, MFA, RLS por defecto y sesión en memoria no están implementados aún).
- **Despliegue**: subir `dist` completo al subdominio con `.htaccess`; borrar chunks viejos de `assets`.
- **Prueba de carga** con 50 sesiones simuladas antes de la jornada.
- **Producción anterior** (`electoral.strategosfp.com/delegados`, compilación del 28 ago): decidir si se apaga o redirige a `juntas`.

## Regla aprendida

- Las comprobaciones al final de una migración no pueden llamar funciones que exijan `portal_rol()`: el editor SQL no tiene sesión y el fallo revierte toda la migración.
- Al recorrer `pg_proc` con `pg_get_functiondef`, filtrar siempre `p.prokind = 'f'`: las funciones agregadas hacen fallar la consulta y revierten la migración.

## Hecho

- Cruce Resolución JCE 08-2026 cerrado: fases 83, 83b y 84 aplicadas; 1,409 de 1,476 electos emparejados y marcados en Análisis Electoral con cargo definitivo; cédula guardada en aspirantes; foto de mayo y vistas creadas. Resultado: FP 457 cargos, 188 titulares (1.º), 40 presidencias (PRM 70); presencia en 160 de 162 juntas (30 sep 2026).

- Resolución JCE 08-2026 leída por OCR y validada (162 juntas, 1,476 cargos, cédulas con dígito verificador correcto). Fase 83 escrita y probada en PostgreSQL local; consultas de cruce R1-R8 documentadas (30 sep 2026).

- Fase 82 aplicada y 8.9.0 en producción: Manuel no ve Postulantes y Avance funciona por niveles (28 sep 2026).

- Fase 81 aplicada; Manuel ve los expedientes de su provincia. Fase 82 escrita: parámetro «Ver postulantes» (en falso para todos salvo administración), lectura de lo propio siempre, pantalla Avance para todos los roles con niveles región › provincia › municipio › distrito › colegios, Asignación solo con el parámetro (28 sep 2026).

- Función «acceso» redesplegada, `dist` 8.8.0 en producción, fase 73 aplicada, configuración de traslados repuesta. Fase 81 escrita: lectura por provincia para nivel provincial sin municipio (27 sep 2026).

- Prueba de Manuel cerrada: «¿Olvidaste tu PIN?» → bandeja → restablecer → vuelve a pedir la fecha (fase 79). Confirmación de la SNE del 23 sep se conserva, como está diseñado. Análisis Electoral entra con la cuenta de administración (fase 78) (27 sep 2026).

- Fases 78, 79 y 80 aplicadas. Manuel entró con PIN nuevo, verificó identidad y creó su PIN personal (27 sep 2026).

- Fase 80 escrita: «↺ PIN nuevo» y el restablecimiento por asistente escriben el PIN en usuarios_pin_inicial, con plazo nuevo y de vuelta en «Accesos por enviar» (27 sep 2026).

- Fase 79 escrita: al restablecer un PIN (Gestión o asistente) se borra la verificación de identidad si el parámetro está activo; interruptor en Configuración, ayuda y documento actualizados. Fase 78 escrita para Análisis Electoral (27 sep 2026).

- Fechas solo-día corregidas (se mostraban un día antes). Modal de identidad con día · mes · año en campos separados (23 sep 2026).

- Fases 76 y 77 aplicadas; buscador y ⓘ verificados en producción. Ayuda de administración con las cuatro bandejas: cuándo, por dónde, qué hacer. Acceso: función sin consulta de configuración cuando no hay captcha; perfil y permisos en paralelo (23 sep 2026).

- Causa del bloqueo del administrador confirmada por bitácora: tres fallos de identidad en 3 s con la sesión de administrador desde una segunda pestaña; fase 76 lo impide. Buscador de usuarios por nombre corregido (23 sep 2026).

- Fase 75 aplicada, función «acceso» desplegada, gancho de token creado. Bloqueo por intentos probado: aparece en Usuarios bloqueados y se habilita. Modal de identidad con salidas «Verificar más tarde» y «Salir» (23 sep 2026).

- Fase 75 escrita: el gancho de verificación de contraseña no existe en el plan Pro; el acceso pasa por la Edge Function «acceso» y el gancho Customize Access Token niega sesiones a bloqueados y a quien rodee la función (23 sep 2026).

- Fase 74 aplicada. Gestión tiene pestaña «Accesos y seguridad» con cuatro bandejas plegables: solicitudes de PIN, bloqueados, primeros ingresos por confirmar, accesos por enviar (23 sep 2026).

- Fase 74 escrita: bloqueo por intentos (gancho de Auth), verificación con el padrón, PIN con caducidad, confirmación de la SNE, «¿Olvidaste tu PIN?» reconstruido, bandeja de envío de accesos, todo parametrizable en Configuración. Documentado en docs/SEGURIDAD_ACCESO.md (23 sep 2026).

- Confirmado con la cédula 00100256783: «E» = vota en el exterior y el colegio del padrón es el de origen. Fase 73 escrita. WhatsApp enmascarado igual que el teléfono en Postulantes (23 sep 2026).

- Máscara 809-000-0000 en teléfono y WhatsApp (registro y usuarios). Asignación visible solo para administración y coordinadores regionales (23 sep 2026).

- Fases 69 a 72 aplicadas. Pruebas de traslado completadas con el administrador: autorizar → aprobar, bloquear, rechazar → reabrir → aprobar. Contador del menú al día (23 sep 2026).

- Fase 63 aplicada; disparador `aa_p28_control_colegio` confirmado primero (23 sep 2026).
- Fase 65 aplicada y confirmada en pantalla (Santo Domingo de Guzmán). Fase 64 aplicada. Prueba de Camilo ok (23 sep 2026).
- Corregido: con «Preguntar en cada registro» el selector de colegio no aparecía para quien vota en el municipio.
- Fase 68 aplicada; avance visible en usuarios. Orden por columnas en la lista de usuarios. Fase 69 escrita: formulario en blanco e individual habilitables desde Configuración y aplicados en la base (23 sep 2026).
- Formulario impreso: bloque B imprime recinto, colegio, distrito y circunscripción del colegio asignado o solicitado. Lista de usuarios con avance (registrados de meta, %, colegios). Enlace de los mensajes cambiado a juntas.strategosfp.com (23 sep 2026).
- Fases 66 y 67 aplicadas. Gestión reorganizada en pestañas (Usuarios · Asistente · Configuración), menos color, sin menciones a Supabase en pantalla; Ayuda actualizada con asignación y configuración (23 sep 2026).
- Fase 67 escrita: bloquear / autorizar / permitir, límite del encargado parametrizado, permisos de asignación cerrados; tarjetas de Asignación activas (23 sep 2026).
- Fase 66 escrita: OCLEE sin traslado.
- Fase 65 escrita: diagnóstico confirmó que `_mapeo_municipio` traducía Distrito Nacional como Tamboril; buscar_cedula pasa a `_unidades_jce` (23 sep 2026).
- Fase 64 escrita: el encargado solo registra a quien vota en su municipio (23 sep 2026).
- Fase 63 escrita y pantallas de registro y Asignación fortalecidas (23 sep 2026): Opción 1, cuatro mejoras, contador en el menú.
- Fase 62 aplicada (23 sep 2026); cobertura validada: 4 colegios incompletos corresponden a los 4 registros con colegio asignado.
- Fase 62 escrita (23 sep 2026): las cuatro funciones restantes cuentan por colegio asignado.
- Fase 61 aplicada (23 sep 2026): cobertura sin error y contada por colegio asignado.
- v8.7.0: versión visible, `.htaccess` con cabeceras (verificado en servidor), captcha Turnstile con interruptor administrado, fases 58 a 60, paso Confirmar del registro muestra el colegio asignado, git iniciado.
