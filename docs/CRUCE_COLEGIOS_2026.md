# Cruce de colegios electorales nuevos 2024-2028 · JCE, cortes 23 y 30 de septiembre de 2026

Archivos en `electoral/jce-2026-09/`. Tablas de Análisis Electoral: `public.jce_recinto`, `public.jce_colegio` (esquema compartido).

## Qué dicen los archivos de la JCE (ya cuadrados entre sí)

| Archivo | Contenido | Cifras |
|---|---|---|
| 03 (xlsx) | Totales nacionales al 30 sep 2026 | 4,568 recintos · 18,545 colegios · propuestas 0 a 11 = 1,218 colegios (983 en recinto existente, 235 en recinto nuevo) · traslados 886 colegios / 284 recintos · correcciones de nombre 995 recintos |
| 04 (xls) y 05 (PDF) | Lista de los colegios creados 2024-2028, corte 30 sep | 1,218 colegios · 140 municipios · 1,172 recintos distintos · sin códigos repetidos |
| 08 (PDF) | Misma lista, corte 23 sep, con electores y año de creación | 1,157 colegios · 163,249 electores · 2024: 137 · 2025: 554 · 2026: 466 |
| 06 y 07 (PDF) | Colegios preliminares 2026 | 382 colegios · 105 municipios · 4,509 electores (subconjunto exacto de 08) |
| 12 (xlsx) | Cambios de demarcación de personas al 21 sep | 121,295 ciudadanos (no es de colegios; sirve para otro análisis) |
| 02 (PDF) | Empadronados por OCLEE según circunscripción | exterior |

Hallazgos del cuadre:

- Los 1,218 del 30 sep **contienen** a los 1,157 del 23 sep. Los 61 que faltan son la **propuesta 10** (San Cristóbal 15, Santo Domingo Norte 28, Santo Domingo Este 7, Hato Mayor 4, Sabaneta 2, Baní, El Factor, Las Guáranas, Villa La Mata, Pedro Brand 1 cada uno). No tienen electores todavía.
- En **20 colegios** el recinto del 23 sep es distinto del recinto del 30 sep (traslados de última hora, 9 en Santo Domingo Oeste). Se guardó el código anterior en `codigo_recinto_23sep`.
- El código de colegio es único **dentro del municipio**, no a nivel nacional. El código de recinto también.
- `jce_recinto` no guarda el municipio: se llega por `jce_colegio.id_municipio`. Por eso un recinto nuevo sin colegios no se puede ubicar por código solo.

## Fase 87a (ya escrita, aplicar primero)

`supabase/migrations/20261007000089_fase87a_jce_colegios_2026_respaldo_y_carga.sql`: respalda `jce_recinto` y `jce_colegio` en `*_bak_20261007`, crea `public.jce_colegios_nuevos_2026` con los 1,218 y los cruza. **No toca las tablas reales.** Esperado: total 1218, con_electores 1157, preliminares 382.

## Consultas de diagnóstico (una por vez, cada una devuelve un solo resultado)

**C1. Lo que tenemos hoy** (comparar con JCE: 4,568 recintos y 18,545 colegios):

```sql
select (select count(*) from public.jce_recinto) as recintos,
       (select count(*) from public.jce_recinto where estatus = 'A') as recintos_activos,
       (select count(*) from public.jce_colegio) as colegios,
       (select count(distinct id_municipio) from public.jce_colegio) as municipios_con_colegios,
       (select sum(cantidad_inscritos) from public.jce_colegio) as inscritos,
       (select count(*) from public.jce_colegio where cantidad_inscritos is null) as colegios_sin_inscritos,
       (select max(id_colegio) from public.jce_colegio) as max_id_colegio,
       (select max(id) from public.jce_recinto) as max_id_recinto;
```

**C2. Situación de los 1,218 frente a lo que hay:**

```sql
select situacion, count(*) as colegios, count(distinct id_municipio) as municipios, sum(electores) as electores
  from public.jce_colegios_nuevos_2026 group by 1 order by 1;
```

**C3. Los que ya existen: ¿coinciden los electores?**

```sql
select count(*) as ya_existen,
       count(*) filter (where c.cantidad_inscritos = n.electores) as mismos_electores,
       count(*) filter (where c.cantidad_inscritos <> n.electores) as electores_distintos,
       count(*) filter (where n.electores is null) as sin_dato_jce,
       sum(c.cantidad_inscritos) as inscritos_nuestros, sum(n.electores) as electores_jce
  from public.jce_colegios_nuevos_2026 n join public.jce_colegio c on c.id_colegio = n.id_colegio_actual;
```

**C4. Nombres de municipio: la «Serie» del reporte debe ser el id JCE del municipio** (esperado: 0 filas distintas):

```sql
select n.id_municipio, n.municipio_jce, m.descripcion as en_base
  from (select distinct id_municipio, municipio_jce from public.jce_colegios_nuevos_2026) n
  left join public.jce_municipio m on m.id = n.id_municipio
 where m.id is null or upper(m.descripcion) <> upper(n.municipio_jce)
 order by 1;
```

**C5. Recintos que faltan por completo** (candidatos a crear; el sector ayuda a ubicar el `id_sector_paraje`):

```sql
select n.id_municipio, n.municipio_jce, n.codigo_recinto, n.recinto, n.sector, count(*) as colegios,
       (select string_agg(sp.id::text || ' ' || sp.descripcion, ' | ')
          from public.jce_sector_paraje sp join public.jce_ciudad_seccion cs on cs.id = sp.id_ciudad_seccion
         where cs.id_municipio = n.id_municipio and upper(sp.descripcion) = upper(n.sector)) as sector_en_base
  from public.jce_colegios_nuevos_2026 n
 where n.situacion = 'falta colegio y recinto'
 group by 1,2,3,4,5 order by 1,3;
```

**C6. Los 20 colegios que cambiaron de recinto entre cortes, con lo que tenemos:**

```sql
select n.id_municipio, n.municipio_jce, n.codigo_colegio, n.codigo_recinto_23sep as recinto_23sep, n.codigo_recinto as recinto_30sep,
       r.codigo_recinto as recinto_en_base, n.situacion
  from public.jce_colegios_nuevos_2026 n
  left join public.jce_colegio c on c.id_colegio = n.id_colegio_actual
  left join public.jce_recinto r on r.id = c.id_recinto
 where n.codigo_recinto_23sep is not null order by 1,3;
```

Con C1 a C6 se decide la fase 87b (inserciones), que irá en este orden: recintos nuevos → colegios en recinto existente → colegios en recinto nuevo → electores, con conteos antes y después y sin tocar lo que ya existe.
