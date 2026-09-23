# Pendientes · Portal de Delegados 2028

Lista viva. Se actualiza en cada sesión de trabajo. Lo primero de «Próximo» es lo que sigue.

## Próximo

1. **Aplicar fase 64** (encargado limitado a su municipio, también en la base). Esperado: 1 fila ok = true.
2. **Aplicar fase 65** (la búsqueda de cédula usa la correspondencia definitiva; corrige «vota en Tamboril»). Esperado: cero filas.
3. **Subir `dist`** al subdominio (Registrar, Asignación y menú cambiaron).
4. **Probar el flujo completo** con el usuario administrador: asignar a Camilo (0129-00001) con la sugerencia preseleccionada; registrar una cédula de otro municipio con un usuario encargado (no admin) y ver que ahora pasa; en Gestión → Traslados activar «requiere autorización», registrar otra de otra provincia y ver que aparece en «Esperan autorización» y no cuenta; aprobarla en Dirigencia → Traslados y ver que pasa a contar.
4. **Cloudflare, Parte 2**: crear cuenta, importar DNS, cambiar nameservers en GoDaddy. Avisar «activo».

Nota de trabajo: los commits los hace Claude; el `push` lo hace Nestor desde GitHub Desktop después de cada sesión.

## En curso

- **Seguridad de base** (fases 58, 59, 59b, 60 aplicadas). Falta: desactivar registro público en Supabase Auth y activar captcha en Supabase cuando exista el widget de Turnstile (Cloudflare Parte 4).
- **Guardar en el repositorio una copia de las funciones que hoy viven en la base** (las fases 29 a 57 se perdieron como archivos, pero las funciones siguen en Supabase). Cómo: en el editor SQL, correr la consulta de `string_agg(pg_get_functiondef…)`, y en el panel de resultados usar «Export» → «Download CSV»; el archivo cae en Descargas. Decirle a Claude el nombre del archivo y él lo convierte en migración. No es urgente.

## Pendiente

- **Fase 63 · control formal del colegio en el registro** (depende de la decisión del punto 1 de Próximo; hallazgo: hoy el alcance configurado es solo informativo, el encargado nunca puede registrar fuera de su municipio): disparador `before insert/update` en `postulantes_2028` que verifique que `colegio_asignado` pertenece al municipio, recalcule los datos del padrón en la base y proteja `traslado_estado`, `autorizado_por` y columnas sensibles para quien no sea admin.
- **Fase 64 · función definer para Strategos** (`padron_buscar`, `padron_resumen_municipio`, `padron_por_cedula`) y retirar de nuevo el `select` de `jce_padron` a `authenticated`.
- **Solicitud de PIN rota**: el botón «Solicitar» de «¿Olvidaste tu PIN?» llama a `portal_delegados_solicitar_pin`, que no existe; muestra éxito sin guardar nada. Diseñar autoservicio: cédula + código de un solo uso por WhatsApp/Telegram + PIN nuevo.
- **Formulario impreso**: el bloque B «Trabajará en» sale vacío aunque haya `colegio_asignado`.
- **Listado de Postulantes** no muestra el colegio asignado.
- **Sesión en el navegador**: decidir memoria pura (documento de seguridad) o persistencia con caducidad por inactividad.
- **PIN inicial de 6 dígitos**: exigir PIN personal de 8 o más caracteres.
- **Documentos de seguridad**: corregir la columna «Estado» (Cloudflare, MFA, RLS por defecto y sesión en memoria no están implementados aún).
- **Despliegue**: subir `dist` completo al subdominio con `.htaccess`; borrar chunks viejos de `assets`.
- **Prueba de carga** con 50 sesiones simuladas antes de la jornada.
- **Producción anterior** (`electoral.strategosfp.com/delegados`, compilación del 28 ago): decidir si se apaga o redirige a `juntas`.

## Regla aprendida

- Las comprobaciones al final de una migración no pueden llamar funciones que exijan `portal_rol()`: el editor SQL no tiene sesión y el fallo revierte toda la migración.

## Hecho

- Fase 63 aplicada; disparador `aa_p28_control_colegio` confirmado primero (23 sep 2026).
- Fase 65 escrita: diagnóstico confirmó que `_mapeo_municipio` traducía Distrito Nacional como Tamboril; buscar_cedula pasa a `_unidades_jce` (23 sep 2026).
- Fase 64 escrita: el encargado solo registra a quien vota en su municipio (23 sep 2026).
- Fase 63 escrita y pantallas de registro y Asignación fortalecidas (23 sep 2026): Opción 1, cuatro mejoras, contador en el menú.
- Fase 62 aplicada (23 sep 2026); cobertura validada: 4 colegios incompletos corresponden a los 4 registros con colegio asignado.
- Fase 62 escrita (23 sep 2026): las cuatro funciones restantes cuentan por colegio asignado.
- Fase 61 aplicada (23 sep 2026): cobertura sin error y contada por colegio asignado.
- v8.7.0: versión visible, `.htaccess` con cabeceras (verificado en servidor), captcha Turnstile con interruptor administrado, fases 58 a 60, paso Confirmar del registro muestra el colegio asignado, git iniciado.
