# Pendientes · Portal de Delegados 2028

Lista viva. Se actualiza en cada sesión de trabajo. Lo primero de «Próximo» es lo que sigue.

## Próximo

1. **Aplicar fase 61** en Supabase (corrige el 400 de cobertura y cuenta por colegio asignado). Verificar en Inicio que «Colegios cubiertos» deja de ser 0.
2. **Subir el repositorio**: `git push -u origin main`.
3. **Cloudflare, Parte 2**: crear cuenta, importar DNS, cambiar nameservers en GoDaddy. Avisar «activo».

## En curso

- **Seguridad de base** (fases 58, 59, 59b, 60 aplicadas). Falta: desactivar registro público en Supabase Auth y activar captcha en Supabase cuando exista el widget de Turnstile (Cloudflare Parte 4).
- **Recuperar las fases 29 a 57**: exportar las funciones actuales de `delegados` como archivo desde el editor SQL (Export → CSV) y convertirlas en migración de referencia.

## Pendiente

- **Fase 62 · alinear cobertura por colegio asignado** en `portal_kpi_distritos`, `portal_kpi_filtro`, `portal_bot_nivel`, `portal_bot_resumen` (hoy cuentan por `id_colegio_padron`).
- **Fase 63 · control formal del colegio en el registro**: disparador `before insert/update` en `postulantes_2028` que verifique que `colegio_asignado` pertenece al municipio, recalcule los datos del padrón en la base y proteja `traslado_estado`, `autorizado_por` y columnas sensibles para quien no sea admin.
- **Fase 64 · función definer para Strategos** (`padron_buscar`, `padron_resumen_municipio`, `padron_por_cedula`) y retirar de nuevo el `select` de `jce_padron` a `authenticated`.
- **Solicitud de PIN rota**: el botón «Solicitar» de «¿Olvidaste tu PIN?» llama a `portal_delegados_solicitar_pin`, que no existe; muestra éxito sin guardar nada. Diseñar autoservicio: cédula + código de un solo uso por WhatsApp/Telegram + PIN nuevo.
- **`autorizado_por` semántico**: hoy lleva el nombre de quien registra aunque no hubo autorización. Decidir si se vacía cuando el estado es «permitido».
- **Formulario impreso**: el bloque B «Trabajará en» sale vacío aunque haya `colegio_asignado`.
- **Listado de Postulantes** no muestra el colegio asignado.
- **Sesión en el navegador**: decidir memoria pura (documento de seguridad) o persistencia con caducidad por inactividad.
- **PIN inicial de 6 dígitos**: exigir PIN personal de 8 o más caracteres.
- **Documentos de seguridad**: corregir la columna «Estado» (Cloudflare, MFA, RLS por defecto y sesión en memoria no están implementados aún).
- **Despliegue**: subir `dist` completo al subdominio con `.htaccess`; borrar chunks viejos de `assets`.
- **Prueba de carga** con 50 sesiones simuladas antes de la jornada.
- **Producción anterior** (`electoral.strategosfp.com/delegados`, compilación del 28 ago): decidir si se apaga o redirige a `juntas`.

## Hecho

- v8.7.0: versión visible, `.htaccess` con cabeceras (verificado en servidor), captcha Turnstile con interruptor administrado, fases 58 a 60, paso Confirmar del registro muestra el colegio asignado, git iniciado.
