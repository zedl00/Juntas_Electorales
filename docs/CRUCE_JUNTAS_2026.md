# Cruce de la Resolución JCE 08-2026 con Análisis Electoral

Fuente: certificación de la Resolución No. 08-2026 (29 sep 2026), integración preliminar de las 162 juntas electorales. Leída por OCR (Vision de macOS), validada: 162 juntas, 1,476 cargos, dígito verificador correcto en todas las cédulas, sin repetidas. Copia en `docs/juntas_2026_resolucion_08.csv`.

Carga y emparejamiento automático: `supabase/migrations/20260930000084_fase83_jce_juntas_2026.sql` (idempotente; se puede repetir después de correcciones manuales).

Cómo empareja: junta → municipio por `junta_nombre` y `nombre`; cédula → nombre oficial del padrón; persona → aspirante por nombre completo dentro del municipio, luego por apellidos del padrón + primer nombre, luego por apellido + primer nombre del OCR. El partido sale del aspirante emparejado. Lo que no empareja queda para revisión manual (R5, R6).

Cada consulta es una sola sentencia.

## R0 · Verificación de la lectura (OCR) contra el padrón
R0a · cédulas de la resolución que no existen en el padrón (esperado: 0 o muy pocas):
```sql
select junta, municipio_jce, orden, cargo, cedula_fmt, nombre from public.jce_juntas_2026 where nombre_padron is null order by junta, orden;
```
R0b · nombres leídos que no coinciden con el nombre oficial del padrón (revisar a ojo; si el OCR leyó mal, el nombre del padrón es el que manda):
```sql
select junta, municipio_jce, orden, cedula_fmt, nombre as leido, nombre_padron as padron from public.jce_juntas_2026 where nombre_padron is not null and public._norm_txt(nombre) <> public._norm_txt(nombre_padron) order by junta, orden;
```
R0c · resumen de la lectura en una fila:
```sql
select count(*) as cargos, count(distinct junta) as juntas, count(*) filter (where nombre_padron is null) as sin_padron, count(*) filter (where nombre_padron is not null and public._norm_txt(nombre) = public._norm_txt(nombre_padron)) as nombre_igual_al_padron, count(*) filter (where nombre_padron is not null and public._norm_txt(nombre) <> public._norm_txt(nombre_padron)) as nombre_distinto from public.jce_juntas_2026;
```

## R1 · Juntas sin municipio (deben ser 0; si hay, corregir con R1b y repetir la fase 83)
```sql
select junta, municipio_jce from public.jce_juntas_2026 where municipio_id is null group by 1, 2 order by 1;
```
R1b · corrección manual (sustituir número de junta e id de municipio):
```sql
update public.jce_juntas_2026 set municipio_id = 0 where junta = 0;
```

## R2 · Resumen por partido
```sql
select coalesce(p.siglas, p.nombre, '(sin emparejar)') as partido, count(*) as cargos, count(*) filter (where j.titular) as titulares, count(*) filter (where j.cargo = 'Presidente') as presidentes, count(*) filter (where not j.titular) as suplentes, count(distinct j.junta) as juntas from public.jce_juntas_2026 j left join public.partidos p on p.id = j.partido_id group by 1 order by 2 desc;
```

## R3 · Fuerza del Pueblo, detalle por junta y comparación con lo marcado en la aplicación
```sql
select j.junta, j.municipio_jce, j.cargo, coalesce(j.nombre_padron, j.nombre) as persona, a.cargo_aspira as aspiraba_a, a.seleccionado as marcado_en_app, a.cargo_electo as cargo_electo_app, case when a.cargo_electo = j.cargo then 'igual' when a.cargo_electo is null then 'sin cargo en app' else 'distinto' end as comparacion, j.match_tipo from public.jce_juntas_2026 j join public.aspirantes a on a.id = j.aspirante_id join public.partidos p on p.id = a.partido_id where p.siglas = 'FP' or p.nombre ilike '%fuerza del pueblo%' order by j.junta, j.orden;
```

## R4 · Marcados como seleccionados en la aplicación que NO aparecen en la resolución
```sql
select a.id, m.nombre as municipio, concat_ws(' ', a.nombres, a.apellido1, a.apellido2) as persona, p.siglas as partido, a.cargo_electo from public.aspirantes a join public.municipios m on m.id = a.municipio_id left join public.partidos p on p.id = a.partido_id where a.seleccionado and a.activo and not exists (select 1 from public.jce_juntas_2026 j where j.aspirante_id = a.id) order by m.nombre, a.apellido1;
```

## R5 · Miembros de la resolución sin emparejar (revisión manual)
```sql
select j.junta, j.municipio_jce, j.orden, j.cargo, j.cedula_fmt, coalesce(j.nombre_padron, j.nombre) as persona, (j.nombre_padron is null) as sin_padron from public.jce_juntas_2026 j where j.aspirante_id is null order by j.junta, j.orden;
```
R6 · emparejar a mano (sustituir cédula de 11 dígitos e id del aspirante):
```sql
update public.jce_juntas_2026 j set aspirante_id = a.id, partido_id = a.partido_id, match_tipo = 'manual' from public.aspirantes a where j.cedula = '00000000000' and a.id = 0;
```

## R7 · Cómo queda cada junta para Fuerza del Pueblo
```sql
select j.junta, j.municipio_jce, count(*) filter (where p.siglas = 'FP' or p.nombre ilike '%fuerza del pueblo%') as fp_cargos, count(*) filter (where (p.siglas = 'FP' or p.nombre ilike '%fuerza del pueblo%') and j.titular) as fp_titulares, bool_or((p.siglas = 'FP' or p.nombre ilike '%fuerza del pueblo%') and j.cargo = 'Presidente') as fp_presidente, count(*) filter (where j.aspirante_id is null) as sin_emparejar, count(*) as cargos from public.jce_juntas_2026 j left join public.partidos p on p.id = j.partido_id group by 1, 2 order by fp_titulares desc, fp_cargos desc, j.junta;
```

## R8 · Solo después de revisar: marcar en la aplicación lo que dice la resolución
Marca como seleccionado y pone el cargo electo a los aspirantes emparejados. No desmarca a nadie.
```sql
with u as (update public.aspirantes a set seleccionado = true, cargo_electo = j.cargo, fecha_seleccion = coalesce(a.fecha_seleccion, now()), updated_at = now() from public.jce_juntas_2026 j where j.aspirante_id = a.id and (not coalesce(a.seleccionado, false) or a.cargo_electo is distinct from j.cargo) returning a.id) select count(*) as actualizados from u;
```

## Después del cruce (30 sep 2026)

- `fase83b` registra lo ejecutado a mano: 11 juntas mapeadas, dos pasadas tolerantes y 16 emparejamientos revisados uno a uno.
- `fase84` guarda la cédula de la resolución en `aspirantes.cedula` (1,409 personas) y crea la vista `public.vista_juntas_2026`.

Consultas sobre la vista, una sentencia cada una:

Una junta completa:
```sql
select junta, cargo, persona, partido, emparejamiento, cedula from public.vista_juntas_2026 where municipio_jce = 'AZUA' order by orden;
```
Resumen por partido:
```sql
select coalesce(partido, '(no está en la base)') as partido, count(*) as cargos, count(*) filter (where titular) as titulares, count(*) filter (where cargo = 'Presidente') as presidentes, count(distinct junta) as juntas from public.vista_juntas_2026 group by 1 order by 2 desc;
```
Fuerza del Pueblo por junta:
```sql
select junta, municipio, count(*) as cargos_fp, count(*) filter (where titular) as titulares_fp, bool_or(cargo = 'Presidente') as presidente_fp from public.vista_juntas_2026 where partido = 'FP' group by 1, 2 order by 3 desc, 1;
```

## Análisis mayo → resolución (vista_cambios_mayo_2026)

Decisión del 30 sep: no se quita ninguna marca. La foto de mayo queda en `jce_seleccion_mayo_2026`.

A1 · Qué pasó con la gente de mayo, por partido:
```sql
select coalesce(partido_mayo, '(sin partido)') as partido_mayo, count(*) as personas, count(*) filter (where situacion = 'se mantiene') as se_mantienen, count(*) filter (where situacion = 'cambió de cargo') as cambiaron_de_cargo, count(*) filter (where situacion = 'sustituida') as sustituidas from public.vista_cambios_mayo_2026 group by 1 order by 2 desc;
```
A2 · Sustituciones: de qué partido salió el cargo y a qué partido fue:
```sql
select coalesce(partido_mayo, '(sin partido)') as salio_de, coalesce(partido_de_quien_ocupa, case when ocupante_fuera_de_la_base then '(no está en la base)' else '(sin partido)' end) as paso_a, count(*) as cargos, count(*) filter (where cargo_mayo in ('Presidente','Primer Vocal','Segundo Vocal','Tercer Vocal','Cuarto Vocal')) as titulares from public.vista_cambios_mayo_2026 where situacion = 'sustituida' group by 1, 2 order by 3 desc;
```
A3 · Lista completa de sustituidas, con quién ocupa el cargo:
```sql
select municipio, cargo_mayo, persona as salio, partido_mayo, quien_ocupa_su_cargo as entro, partido_de_quien_ocupa as partido_entro from public.vista_cambios_mayo_2026 where situacion = 'sustituida' order by municipio, cargo_mayo;
```
A4 · Por municipio: cuánto cambió cada junta respecto a mayo:
```sql
select municipio, count(*) as de_mayo, count(*) filter (where situacion = 'se mantiene') as se_mantienen, count(*) filter (where situacion = 'cambió de cargo') as cambiaron_de_cargo, count(*) filter (where situacion = 'sustituida') as sustituidas from public.vista_cambios_mayo_2026 group by 1 order by sustituidas desc, municipio;
```
A5 · Saldo por partido en los municipios que tenían lista en mayo: cargos que tenía en mayo y cargos que tiene en la resolución:
```sql
select coalesce(p.siglas, '(sin partido / fuera de la base)') as partido, count(distinct s.aspirante_id) as cargos_en_mayo, count(distinct (j.junta, j.orden)) as cargos_en_resolucion from public.partidos p full join public.jce_seleccion_mayo_2026 s on s.partido_id = p.id full join public.jce_juntas_2026 j on j.partido_id = p.id and j.municipio_id in (select distinct municipio_id from public.jce_seleccion_mayo_2026) group by 1 having count(distinct s.aspirante_id) > 0 or count(distinct (j.junta, j.orden)) > 0 order by 3 desc;
```
A6 · Una junta completa, mayo frente a hoy:
```sql
select cargo, persona, partido, estaba_en_mayo, respecto_a_mayo, cargo_mayo from public.vista_juntas_2026 where municipio_jce = 'BOCA CHICA' order by orden;
```
