-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 10 · DISTRITOS REALES
--  (vía sector/paraje → ciudad-sección → distrito municipal)
-- ----------------------------------------------------------------
--  HALLAZGO DEFINITIVO (datos reales del 22/08):
--   · jce_municipio tiene 432 filas: 195 cabeceras (id_municipio_padre
--     = su propio id) y 236 DISTRITOS MUNICIPALES (padre distinto,
--     marcados dm = '1').
--   · PERO los distritos tienen 0 colegios en jce_colegio: TODOS los
--     colegios cuelgan de la cabecera (ej.: Santo Domingo Este 1,581
--     colegios; su distrito San Luis, 0).
--   · La pertenencia real de un colegio a su distrito vive en:
--       jce_colegio.id_recinto → jce_recinto.id_sector_paraje
--       → jce_sector_paraje.id_ciudad_seccion
--       → jce_ciudad_seccion.id_distrito_municipal
--
--  Esta fase usa esa cadena. No modifica ninguna tabla del SNE.
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Idempotente.
--  Reemplaza a las fases 3, 4, 6, 7, 8 y 9.
-- ================================================================

set search_path = delegados, public;

drop view if exists delegados.portal_circunscripciones cascade;
drop view if exists delegados.portal_distritos cascade;
drop view if exists delegados.portal_metas_municipio cascade;
drop view if exists delegados._unidades_jce cascade;
drop view if exists delegados._colegio_distrito cascade;

-- ----------------------------------------------------------------
-- 1. CADA COLEGIO CON SU DISTRITO REAL
-- ----------------------------------------------------------------
create view delegados._colegio_distrito as
select c.id_colegio::integer                                  as id_colegio,
       c.id_municipio::integer                                as jce_cabecera,
       coalesce(cs.id_distrito_municipal, c.id_municipio)::integer as jce_distrito,
       c.id_recinto::integer                                  as id_recinto,
       rc.id_circunscripcion::integer                         as circ_id
from public.jce_colegio c
left join public.jce_recinto       rc on rc.id = c.id_recinto
left join public.jce_sector_paraje sp on sp.id = rc.id_sector_paraje
left join public.jce_ciudad_seccion cs on cs.id = sp.id_ciudad_seccion;

alter view delegados._colegio_distrito owner to postgres;
grant select on delegados._colegio_distrito to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. DEMARCACIONES DE CADA MUNICIPIO DE LA APLICACIÓN
--    (su cabecera + los distritos que no tienen municipio propio)
-- ----------------------------------------------------------------
create view delegados._unidades_jce as
with mapeo as (   -- app municipio → demarcación JCE (solo filas con municipio real)
  select mm.id_actual::integer as municipio_id, mm.id_jce::integer as jce_id
    from public._mapeo_municipio mm
    join public.municipios m on m.id = mm.id_actual
  union
  select m.id::integer, m.id::integer          -- respaldo por identidad si falta el mapeo
    from public.municipios m
   where not exists (select 1 from public._mapeo_municipio mm where mm.id_actual = m.id)
     and exists (select 1 from public.jce_municipio jm where jm.id = m.id)
),
reclamadas as (select jce_id from mapeo)   -- demarcaciones con municipio propio en la app
select mp.municipio_id, mp.jce_id,
       initcap(lower(coalesce(jm.descripcion, 'Demarcación ' || mp.jce_id)))::text as nombre,
       false as es_dm
  from mapeo mp
  left join public.jce_municipio jm on jm.id = mp.jce_id
union all
select mp.municipio_id, jm.id::integer,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text,
       true
  from mapeo mp
  join public.jce_municipio jm
    on jm.id_municipio_padre = mp.jce_id and jm.id <> mp.jce_id
 where jm.id not in (select jce_id from reclamadas);

alter view delegados._unidades_jce owner to postgres;
grant select on delegados._unidades_jce to authenticated, service_role;

-- ----------------------------------------------------------------
-- 3. METAS POR MUNICIPIO (colegios de la cabecera + los de sus distritos)
-- ----------------------------------------------------------------
create view delegados.portal_metas_municipio as
with col as (
  select u.municipio_id, cd.id_colegio, cd.id_recinto, c.cantidad_inscritos
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
    join public.jce_colegio c on c.id_colegio = cd.id_colegio
)
select m.id            as municipio_id,
       m.nombre,
       m.provincia_id,
       coalesce(nullif(trim(m.provincia_nombre), ''), p.nombre) as provincia_nombre,
       case when m.tipo = 'OCLEE' then 'Exterior'
            else coalesce(nullif(trim(p.macroregion), ''), nullif(trim(m.macroregion), ''),
                          jr.descripcion::text, 'Sin región')
       end                                        as macroregion,
       m.tipo,
       m.estatus,
       count(distinct col.id_colegio)             as colegios,
       count(distinct col.id_recinto)             as recintos,
       coalesce(sum(col.cantidad_inscritos), 0)   as electores,
       count(distinct col.id_colegio) * 3         as meta,
       (m.id_municipio_padre is not null)         as es_dm,
       m.id_municipio_padre                       as municipio_padre_id,
       p.tipo                                     as provincia_tipo
from public.municipios m
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join col on col.municipio_id = m.id
group by m.id, p.macroregion, p.nombre, p.tipo, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 4. DISTRITOS con sus colegios reales
-- ----------------------------------------------------------------
create view delegados.portal_distritos as
select u.municipio_id, u.jce_id, u.nombre, u.es_dm,
       count(distinct cd.id_colegio)             as colegios,
       count(distinct cd.id_recinto)             as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct cd.id_colegio) * 3         as meta
from delegados._unidades_jce u
left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
left join public.jce_colegio c on c.id_colegio = cd.id_colegio
group by u.municipio_id, u.jce_id, u.nombre, u.es_dm;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

-- ----------------------------------------------------------------
-- 5. CIRCUNSCRIPCIONES por municipio
-- ----------------------------------------------------------------
create view delegados.portal_circunscripciones as
select u.municipio_id,
       ci.id::integer                             as circ_id,
       coalesce(nullif(trim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct cd.id_colegio)              as colegios,
       count(distinct cd.id_colegio) * 3          as meta
from delegados._unidades_jce u
join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
join public.jce_circunscripcion ci  on ci.id = cd.circ_id
group by u.municipio_id, ci.id, ci.descripcion, ci.codigo_circunscripcion;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
-- 6. COBERTURA POR COLEGIO (agrupada por distrito y circunscripción)
-- ----------------------------------------------------------------
drop function if exists delegados.portal_cobertura_colegios(integer);
drop function if exists delegados.portal_cobertura_colegios(integer, integer);
drop function if exists delegados.portal_cobertura_colegios(integer, integer, integer);
create function delegados.portal_cobertura_colegios(
  p_municipio integer, p_jce integer default null, p_circ integer default null)
returns table (
  distrito text, jce_id integer, circunscripcion text, circ_id integer,
  id_colegio integer, colegio text, recinto text, recinto_dir text,
  inscritos bigint, titulares bigint, suplentes bigint, observadores bigint,
  indistintos bigint, personas bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;
  select v2.provincia_id, v2.macroregion into v_prov, v_reg
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not (
    v_rol = 'admin_sne'
    or (v_rol in ('presidente','secretario_general','enc_electoral') and p_municipio = portal_mun())
    or (v_rol = 'supervisor_provincial' and v_prov = portal_prov())
    or (v_rol = 'coordinador_regional'  and v_reg = portal_region())
  ) then
    raise exception 'Territorio fuera de tu alcance';
  end if;
  if v_dist is not null then p_jce := v_dist::integer; end if;

  return query
  select u.nombre, u.jce_id,
         coalesce(nullif(trim(ci.descripcion),''), 'Circ. ' || ci.codigo_circunscripcion, '—')::text,
         ci.id::integer,
         c.id_colegio::integer,
         coalesce(nullif(trim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion::text,'—')::text,
         coalesce(rc.direccion::text,'')::text,
         coalesce(max(c.cantidad_inscritos),0)::bigint,
         count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
    join public.jce_colegio c on c.id_colegio = cd.id_colegio
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join public.jce_circunscripcion ci on ci.id = cd.circ_id
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where u.municipio_id = p_municipio
     and (p_jce  is null or u.jce_id = p_jce)
     and (p_circ is null or cd.circ_id = p_circ)
   group by u.nombre, u.jce_id, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
            c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by u.es_dm, u.nombre, coalesce(rc.descripcion,''), 6;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------
-- 7. AVANCE POR DISTRITO
-- ----------------------------------------------------------------
create or replace function delegados.portal_kpi_distritos(p_municipio integer)
returns table (
  jce_id integer, distrito text, es_dm boolean,
  colegios bigint, meta bigint, total bigint,
  completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;
  select v2.provincia_id, v2.macroregion into v_prov, v_reg
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not (
    v_rol = 'admin_sne'
    or (v_rol in ('presidente','secretario_general','enc_electoral') and p_municipio = portal_mun())
    or (v_rol = 'supervisor_provincial' and v_prov = portal_prov())
    or (v_rol = 'coordinador_regional'  and v_reg = portal_region())
  ) then
    raise exception 'Territorio fuera de tu alcance';
  end if;

  return query
  with cole as (
    select u.jce_id as jce, u.nombre, u.es_dm, cd.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as n
      from delegados._unidades_jce u
      left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
      left join postulantes_2028 p on p.id_colegio_padron = cd.id_colegio
                                  and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
       and (v_dist is null or u.jce_id = v_dist)
     group by u.jce_id, u.nombre, u.es_dm, cd.id_colegio
  )
  select cole.jce, cole.nombre, cole.es_dm,
         count(cole.id_colegio)::bigint,
         (count(cole.id_colegio) * 3)::bigint,
         coalesce(sum(cole.n), 0)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n >= 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n > 0 and cole.n < 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n = 0)::bigint
    from cole
   group by cole.jce, cole.nombre, cole.es_dm
   order by cole.es_dm, cole.nombre;
end $$;

revoke all on function delegados.portal_kpi_distritos(integer) from public, anon;
grant execute on function delegados.portal_kpi_distritos(integer) to authenticated;

-- ----------------------------------------------------------------
-- 8. COBERTURA RESUMEN por municipio
-- ----------------------------------------------------------------
create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  return query
  with alcance as (
    select v2.municipio_id from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and v2.municipio_id = portal_mun())
         or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region()))
  ),
  cole as (
    select a.municipio_id as mun_id, cd.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as personas
      from alcance a
      join delegados._unidades_jce u on u.municipio_id = a.municipio_id
      join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
      left join postulantes_2028 p on p.id_colegio_padron = cd.id_colegio
                                  and p.municipio_id = a.municipio_id
     group by a.municipio_id, cd.id_colegio
  )
  select cole.mun_id, count(*)::bigint,
         count(*) filter (where personas >= 3),
         count(*) filter (where personas > 0 and personas < 3),
         count(*) filter (where personas = 0)
    from cole group by cole.mun_id;
end $$;

revoke all on function delegados.portal_cobertura_resumen() from public, anon;
grant execute on function delegados.portal_cobertura_resumen() to authenticated;

-- ----------------------------------------------------------------
-- 9. DIAGNÓSTICO
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'municipios',        (select count(*) from portal_metas_municipio),
    'regiones',          (select count(distinct macroregion) from portal_metas_municipio),
    'meta_nacional',     (select sum(meta) from portal_metas_municipio where estatus is null or estatus <> 'I'),
    'unidades_jce',      (select count(*) from delegados._unidades_jce),
    'distritos',         (select count(*) from portal_distritos where es_dm),
    'muns_con_varios',   (select count(*) from (select municipio_id from portal_distritos
                                                 group by municipio_id having count(*) > 1) x),
    'circunscripciones', (select count(*) from portal_circunscripciones),
    'colegios_total',    (select count(*) from public.jce_colegio),
    'colegios_ubicados', (select count(distinct cd.id_colegio) from delegados._colegio_distrito cd
                            join delegados._unidades_jce u on u.jce_id = cd.jce_distrito),
    'colegios_en_dm',    (select count(*) from delegados._colegio_distrito cd
                            where cd.jce_distrito <> cd.jce_cabecera),
    'ejemplo_multi',     (select jsonb_build_object('municipio', v.nombre, 'municipio_id', v.municipio_id,
                                                    'demarcaciones', x.n, 'meta', v.meta)
                            from (select municipio_id, count(*) n from portal_distritos
                                   group by municipio_id order by n desc limit 1) x
                            join portal_metas_municipio v on v.municipio_id = x.municipio_id)
  );
$$;

revoke all on function delegados.portal_diag() from public, anon;
grant execute on function delegados.portal_diag() to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  select jsonb_pretty(delegados.portal_diag());
--  select jce_id, nombre, es_dm, colegios, meta from delegados.portal_distritos
--   where municipio_id = (select id from public.municipios where nombre ilike '%san juan de la maguana%')
--   order by es_dm, nombre;
