-- fase84_vista_juntas_y_cedula.sql · Portal / Análisis Electoral (esquema public)
-- Idempotente.
--
-- 1. Cédula en aspirantes: se guarda la cédula de la resolución en cada aspirante emparejado.
--    A partir de aquí, los cruces con la Junta pueden hacerse por cédula, sin revisar nombres.
-- 2. Vista vista_juntas_2026: cada junta, cada cargo, quién quedó, de qué partido y cómo se
--    emparejó. Para consultar por junta o por partido, o para conectarla a una pestaña.

alter table public.aspirantes add column if not exists cedula text;
create index if not exists aspirantes_cedula_idx on public.aspirantes (cedula);

update public.aspirantes a
   set cedula = j.cedula_fmt, updated_at = now()
  from public.jce_juntas_2026 j
 where j.aspirante_id = a.id and a.cedula is distinct from j.cedula_fmt;

create or replace view public.vista_juntas_2026 as
select j.junta, j.municipio_jce, m.id as municipio_id, m.nombre as municipio, m.provincia_nombre as provincia, m.macroregion,
       j.orden, j.cargo, j.titular, j.cedula_fmt as cedula,
       coalesce(j.nombre_padron, j.nombre) as persona,
       j.aspirante_id, p.id as partido_id, p.siglas as partido, p.nombre as partido_nombre,
       a.cargo_aspira, a.seleccionado as marcado_en_app, a.cargo_electo as cargo_electo_app,
       case when j.aspirante_id is null then 'no está en la base'
            when j.match_tipo = 'nombre_completo' then 'nombre exacto'
            when j.match_tipo = 'manual' then 'revisado a mano'
            else 'nombre aproximado' end as emparejamiento
  from public.jce_juntas_2026 j
  left join public.municipios m on m.id = j.municipio_id
  left join public.aspirantes a on a.id = j.aspirante_id
  left join public.partidos p on p.id = j.partido_id;

grant select on public.vista_juntas_2026 to authenticated;

-- Comprobación. Esperado: 1 fila; aspirantes_con_cedula alrededor de 1,409 y filas_vista = 1476.
select (select count(*) from public.aspirantes where cedula is not null) as aspirantes_con_cedula,
       (select count(*) from public.vista_juntas_2026) as filas_vista;
