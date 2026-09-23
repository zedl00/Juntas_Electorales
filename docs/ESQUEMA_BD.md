# Esquema de Base de Datos — Portal de Delegados 2028

**Secretaría Nacional Electoral · Fuerza del Pueblo**
Base de datos: Supabase (PostgreSQL) · Proyecto `eskdfhjdkcnixkkivjeo`

Este documento identifica **qué objetos pertenecen al Portal de Delegados**, qué tablas existentes **lee** (sin modificarlas), y cómo se organiza el resto del ecosistema de la base de datos que comparte con el sistema SNE, Strategos y los módulos analíticos.

---

## A · Objetos NUEVOS del Portal — esquema propio **`delegados`** (creados por `sql/fase1_setup.sql`)

Todo el portal vive en su **propio esquema de PostgreSQL llamado `delegados`**, separado de `public`. En el panel de Supabase (Table Editor y Database) se ve agrupado bajo ese nombre, identificando de un vistazo qué pertenece a este proyecto. Ventajas directas: nada colisiona con las ~70 tablas existentes, los respaldos del portal se pueden acotar al esquema, y revertirlo por completo es una sola orden: `drop schema delegados cascade;` — sin riesgo para el SNE.

**Requisito de la API (una vez):** Supabase → Settings → API → **"Exposed schemas"** → agregar `delegados`. La aplicación ya está configurada para consultarlo (`db: { schema: 'delegados' }` en el cliente).

### Tabla `delegados.usuarios_territoriales`
Perfiles de acceso al portal, vinculados 1 a 1 con `auth.users`.

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | = `auth.users.id` |
| `cedula` | text UNIQUE | solo dígitos |
| `nombre`, `telefono` | text | |
| `rol` | text CHECK | `presidente` · `secretario_general` · `enc_electoral` · `supervisor_provincial` · `coordinador_regional` · `admin_sne` |
| `municipio_id` | int | territorio (roles municipales) → `municipios.id` |
| `provincia_id` | int | supervisores provinciales → `provincias.id` |
| `region` | text | coordinadores regionales (macroregión) |
| `activo` | boolean | interruptor de acceso |
| `primer_acceso` | boolean | obliga a crear PIN personal al entrar |
| `acuse_instructivo` | timestamptz | fecha del acuse de lectura |
| `ultimo_acceso` | timestamptz | actualizado por `portal_mi_perfil()` |
| `created_by`, `created_at` | | auditoría |

### Tabla `delegados.postulantes_2028`
Registro central de la preselección (delegados, suplentes y observadores).

| Grupo | Columnas |
|---|---|
| Identidad | `id` uuid PK · `numero_formulario` text UNIQUE (folio `NNNN-NNNNN` por municipio, con bloqueo de concurrencia) · `cedula` UNIQUE · `nombres` · `apellido1` · `apellido2` · `sexo` · `fecha_nacimiento` |
| Contacto | `telefono` · `whatsapp` · `email` · `direccion` · `nivel_academico` · `ocupacion` |
| Territorio | `municipio_id` → `municipios.id` · `provincia_id` · `macroregion` (denormalizados por trigger para filtrar rápido) |
| Padrón | `id_colegio_padron` · `codigo_colegio` · `colegio_desc` · `codigo_recinto` · `recinto_nombre` · `circunscripcion` · `lugar_votacion` |
| Postulación | `cargo_postulado` CHECK (`delegado_titular` · `suplente_delegado` · `observador_escrutinio` · `indistinto`) · `requisitos` jsonb (7 claves del Instructivo) · `experiencia_2024` bool · `experiencia_detalle` · `notas` |
| Proceso | `estado` CHECK (`postulado` → `validado` / `devuelto` / `rechazado` → `en_formacion` → `aprobado` / `no_aprobado` → `designado` → `acreditado`) · `validado_por` → `usuarios_territoriales.id` |
| Auditoría | `created_by` · `created_at` · `updated_at` |

### Tabla `delegados.postulantes_bitacora`
Historial automático de cambios (trigger sobre `postulantes_2028`): `id`, `postulante_id`, `accion` (`creado` / `actualizado` / `estado`), `detalle` jsonb (estado anterior/nuevo, campos modificados), `usuario_id`, `created_at`.

### Vista `delegados.portal_metas_municipio`
Catálogo de territorios con metas: `municipio_id`, `nombre`, `tipo` (`OCLEE` para el exterior), `estatus`, `provincia_id`, `provincia_nombre`, `macroregion`, `colegios` (conteo real de `jce_colegio` vía `_mapeo_municipio`), `meta` (= colegios × 3). Es la fuente del selector de territorios y del cálculo de metas; al ser `security definer`-friendly, funciona sin importar las políticas RLS de las tablas base.

### Funciones RPC del esquema `delegados` (`security definer`)
| Función | Propósito |
|---|---|
| `portal_mi_perfil()` | Perfil del usuario conectado + territorio + meta; actualiza `ultimo_acceso` |
| `portal_buscar_cedula(p_ced)` | Búsqueda exacta en `jce_padron` (con reintento en formato `XXX-XXXXXXX-X`), datos de colegio/recinto, mapeo a municipio de la app, experiencia 2024 (blindada), si ya está postulado y si es usuario del portal |
| `portal_kpi(p_municipio)` | Totales del alcance del usuario: registrados, meta, colegios cubiertos, experiencia, hoy, semana, desgloses por estado y cargo |
| `portal_kpi_territorios()` | Una fila por territorio del alcance: total, meta, % (tabla de avance) |
| `portal_pin_cambiado()` | Marca `primer_acceso = false` |
| `portal_acuse_instructivo()` | Registra el acuse de lectura y devuelve la fecha |

### Fase 2 (`sql/fase2_seguimiento_y_auditoria.sql`) añade al mismo esquema

Tabla **`delegados.eventos_sistema`** (bitácora de accesos, consultas de padrón y gestión de usuarios, con detalle jsonb), triggers de auditoría sobre `usuarios_territoriales` y auditoría enriquecida sobre `postulantes_2028` (diff **antes/después campo por campo** en cada edición), y cuatro RPC nuevos: `portal_cobertura_resumen()` (colegios completos/incompletos/sin registro por territorio), `portal_cobertura_colegios(municipio)` (detalle por colegio con recinto y composición Titular/Suplente/Observador), `portal_eventos(límite)` (bitácora unificada, solo admin) y el helper interno `portal_log()`. Las funciones `portal_mi_perfil` y `portal_buscar_cedula` se redefinen para dejar huella de cada acceso y cada consulta.

**Fase 4** (`sql/fase4_distritos_y_regiones.sql`, incluye y supera a la fase 3) alinea la Región con el sistema SNE que funciona — `provincias.macroregion` primero, `'Exterior'` para OCLEE, respaldo `jce_region` — y añade el nivel de **Distritos** desde la fuente JCE: la vista `delegados.portal_distritos` (demarcaciones de `jce_municipio` con su bandera `dm`, colegios y metas por distrito) y `portal_cobertura_colegios(municipio, jce default null)` que ahora devuelve la columna `distrito` y filtra por demarcación. **Fase 3** (histórica) corregía el filtro de Región en la fuente: la vista deriva `macroregion` con `coalesce(municipios.macroregion, provincias.macroregion, jce_region.descripcion)` vía `provincias.region_id`, de modo que las regiones aparecen aunque el texto libre esté vacío — sin tocar ninguna tabla del SNE. La vista además expone `es_dm` y `municipio_padre_id` para el encadenamiento Municipio → Distrito Municipal, y los alcances regionales de perfil y cobertura usan la misma derivación.

Además: helpers internos `portal_rol()` / `portal_mun()` / `portal_prov()` / `portal_region()` para las políticas, secuencias de folio por municipio, triggers de folio/denormalización/bitácora y **políticas RLS** que limitan cada rol a su demarcación (los roles municipales solo ven su municipio; supervisores su provincia; coordinadores su región; `admin_sne` todo).

---

## B · Tablas EXISTENTES que el portal LEE (solo lectura, únicamente vía RPC o vista)

El portal **jamás** consulta estas tablas directamente desde el navegador ni las modifica; el acceso pasa por las funciones `security definer`, así que funciona sin tocar sus políticas actuales.

| Tabla | Filas | Uso en el portal |
|---|---|---|
| `jce_padron` | 8,136,726* | Búsqueda por cédula: identidad, colegio, lugar de votación |
| `jce_colegio` | 17,327 | Conteo de colegios por municipio → metas (× 3 = **51,981** nacional) |
| `jce_recinto` | 5,783 | Nombre y dirección del recinto en la ficha |
| `jce_municipio` | 432 | Nombre del municipio JCE de la cédula |
| `municipios` | 186 | Catálogo de la app: nombre, provincia, macroregión, `tipo` (OCLEE), estatus |
| `provincias` | 35 | Nombres de provincia |
| `_mapeo_municipio` | 384 | Traducción id JCE ↔ id app (clave del cruce de demarcación) |
| `historial_delegado` | 240 | Experiencia 2024 por cédula (cruce blindado: si cambia, degrada sin romper) |
| `usuarios_sistema` | 20 | Solo para el alta inicial del admin (bloque comentado del SQL) |

\* `jce_padron` marca 8,136,726 en el censo porque `n_live_tup` es un **estimado** del planificador; el conteo real es **8,145,548** (7,281,763 nacional + 863,785 exterior). Un `ANALYZE jce_padron;` acerca el estimado.

**Nota de esquema:** `schemaElectoral.txt` está desactualizado en dos puntos: no incluye la columna `municipios.tipo` (agregada en la corrección OCLEE) ni la tabla `historial_delegado`. Ambas existen en la base real — confirmadas por consultas en vivo.

---

## C · Mapa del resto del ecosistema (contexto, el portal no los usa)

Según el censo de filas ejecutado el 20-ago-2026, agrupado por módulo:

**Núcleo JCE (padrón y catálogos, ~20 tablas).** `jce_padron`, `jce_colegio`, `jce_recinto`, `jce_municipio`, `jce_provincia` (53), `jce_circunscripcion` (48), `jce_oclee` (25), `jce_region` (10), `jce_macroregion` (3), `jce_zona` (4), `jce_sector_paraje` (14,786), `jce_ciudad_seccion` (1,758), `jce_nacionalidad` (207), `jce_ocupacion` (154), `jce_paises` (78), `jce_causa_cancelacion` (37), `jce_categoria` (6), `jce_estado_civil` (2), `jce_cancelacion_tipo` (2), `jce_sexo` (2).

**Estructura FP.** `delegados_fp` (2,629) y `delegados_fp_roles` (1,823) — delegados políticos/técnicos ante JME y OCLEE del ciclo actual; `electos_2024` (3,858) con su `electos_2024_audit` (205); `historial_delegado` (240); `partidos` (43); `secretarias_fp` (1), `vicesecretarios_fp` (2), `cargos_secretaria` (3), `tareas_vicesecretarios` (0).

**Módulos operativos SNE.** `aspirantes` (4,633); consenso: `consenso_asignaciones` (17), `consenso_municipios` (6); incidencias: `incidencias` (1), `incidencias_categorias` (11), `incidencias_documentos` (0).

**Suite Strategos (14 tablas).** `strategos_rol_permisos` (178), `strategos_permisos` (67), `strategos_glosario` (27), `strategos_auditoria` (14), `strategos_interpretaciones` (12), `strategos_recomendaciones_catalogo` (10), `strategos_recomendaciones_sismap` (8), `strategos_roles` (7), `strategos_whatsapp_exports` (4), `strategos_electos_movimientos` (2), `strategos_acciones_municipio` (2), `strategos_usuarios` (1), `strategos_usuario_permisos` (0). Sistema de permisos propio, independiente del portal.

**Analítica municipal (`mun_*`).** `mun_votos_partido` (12,584), `mun_alianzas` (11,262), `mun_sismap_indicadores` (9,391), `mun_sismap_area_score` (2,638), `mun_votos_bloque` (1,105), `mun_sismap_score` (749), `mun_elecciones` (393), `mun_competitividad` (158).

**Geografía (`geo_*`).** `geo_municipios` (393), `geo_funcionarios_electos` (392), `geo_provincias` (32); mapeos `_mapeo_municipio` (384), `_mapeo_provincia` (32); `_config` (1).

**Respaldos (sin RLS — solo copias).** `delegados_fp_backup_abril2026` (966), `delegados_fp_backup_sae2024` (588), `delegados_fp_backup_2024` (350), `municipios_pre_fix_20260508_032626` (393).

**Internas de Supabase — NO tocar.** El censo incluyó tablas de otros esquemas porque la consulta no filtró por `public`: `refresh_tokens`, `sessions`, `users`, `identities`, `mfa_*`, `sso_*`, `saml_*`, `oauth_*`, `flow_state`, `audit_log_entries`, `webauthn_*`, `one_time_tokens` (esquema `auth`); `buckets*`, `objects`, `s3_multipart_*`, `vector_indexes`, `secrets` (`storage`/`vault`); `subscription`, `messages` (`realtime`); `schema_migrations` y `migrations` (por eso aparecen duplicados — existen en varios esquemas, igual que el `electos_2024` repetido del listado). Son la maquinaria interna de autenticación, almacenamiento y tiempo real: **nunca modificarlas**.

### Consulta de censo corregida

Para futuros censos, filtrando solo el esquema de la aplicación:

```sql
select relname as tabla, n_live_tup as filas
from pg_stat_user_tables
where schemaname = 'public'
order by n_live_tup desc;
```

`n_live_tup` es un estimado instantáneo (no bloquea nada). Para conteos exactos de una tabla puntual: `select count(*) from tabla;`.
