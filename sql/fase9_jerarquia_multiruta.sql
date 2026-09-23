-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 9 · JERARQUÍA TERRITORIAL
--  (CUATRO RUTAS) + DIAGNÓSTICO DE ESTRUCTURA CRUDA
-- ----------------------------------------------------------------
--  HALLAZGO (diagnóstico portal_diag del 21/08):
--    · municipios = 186 filas (158 municipios + OCLEE). Los DISTRITOS
--      MUNICIPALES no están cargados en esa tabla.
--    · _mapeo_municipio es 1:1 (384 filas, id_actual distinto en cada
--      una) → cada municipio solo tomaba los colegios de SU CABECERA.
--    · Resultado: meta 49,728 en vez de 51,981 (faltaban 751 colegios,
--      los de los distritos) y ningún municipio mostraba distritos.
--
--  SOLUCIÓN (sin modificar ninguna tabla del SNE):
--    La jerarquía se arma desde jce_municipio.id_municipio_padre:
--    cada demarcación JCE (cabecera o DM) se adscribe al municipio
--    de la aplicación al que pertenece su cabecera.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ (nunca por bloques).
--  Después de fase1, fase2 y fase5. Reemplaza a fase3,4,6,7,8.
--  Idempotente: se puede repetir sin peligro.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. NÚCLEO: unidades JCE adscritas a su municipio de la aplicación
-- ----------------------------------------------------------------
drop view if exists delegados.portal_circunscripciones cascade;
drop view if exists delegados.portal_distritos cascade;
drop view if exists delegados.portal_metas_municipio cascade;
drop view if exists delegados._unidades_jce cascade;
drop function if exists delegados.portal_circunscripciones();
drop function if exists delegados.portal_circunscripciones(integer);
drop function if exists delegados.portal_distritos();
drop function if exists delegados.portal_distritos(integer);

create view delegados._unidades_jce as
with mapeo_valido as (          -- filas del mapeo que apuntan a un municipio real de la app
  select mm.id_jce, mm.id_actual
    from public._mapeo_municipio mm
    join public.municipios m on m.id = mm.id_actual
),
adscritas as (
  -- Ruta 1: la propia demarcación mapeada (siempre)
  select mv.id_actual as municipio_id, mv.id_jce as jce_id from mapeo_valido mv
  union
  -- Ruta 2: jerarquía declarada en jce_municipio.id_municipio_padre
  select mv.id_actual, jm.id
    from mapeo_valido mv
    join public.jce_municipio jm on jm.id_municipio_padre = mv.id_jce and jm.id <> mv.id_jce
  union
  -- Ruta 3: jerarquía derivada de jce_ciudad_seccion (municipio → distrito municipal)
  select mv.id_actual, cs.id_distrito_municipal
    from mapeo_valido mv
    join public.jce_ciudad_seccion cs on cs.id_municipio = mv.id_jce
   where cs.id_distrito_municipal is not null and cs.id_distrito_municipal <> mv.id_jce
  union
  -- Ruta 4: demarcaciones con colegios que el mapeo dejó huérfanas, adscritas por su padre
  select mv.id_actual, jm.id
    from public.jce_municipio jm
    join mapeo_valido mv on mv.id_jce = jm.id_municipio_padre
   where jm.id_municipio_padre is not null
),
final as (
  select distinct a.municipio_id, a.jce_id from adscritas a
   where a.jce_id is not null
)
select f.municipio_id::integer,
       f.jce_id::integer,
       initcap(lower(coalesce(jm.descripcion, 'Demarcación ' || f.jce_id)))::text as nombre,
       (f.jce_id <> mv2.id_jce)                                                   as es_dm
from final f
join public.jce_municipio jm on jm.id = f.jce_id
join (select mm.id_jce, mm.id_actual from public._mapeo_municipio mm
        join public.municipios m on m.id = mm.id_actual) mv2 on mv2.id_actual = f.municipio_id;

alter view delegados._unidades_jce owner to postgres;
grant select on delegados._unidades_jce to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. METAS POR MUNICIPIO (ahora sí incluyen los colegios de los DM)
-- ----------------------------------------------------------------
create view delegados.portal_metas_municipio as
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
       count(distinct c.id_colegio)               as colegios,
       count(distinct c.id_recinto)               as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)     as electores,
       count(distinct c.id_colegio) * 3           as meta,
       (m.id_municipio_padre is not null)         as es_dm,
       m.id_municipio_padre                       as municipio_padre_id,
       p.tipo                                     as provincia_tipo
from public.municipios m
left join public.provincias p   on p.id = m.provincia_id
left join public.jce_region jr  on jr.id = p.region_id
left join delegados._unidades_jce u on u.municipio_id = m.id
left join public.jce_colegio c  on c.id_municipio = u.jce_id
group by m.id, p.macroregion, p.nombre, p.tipo, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 3. DISTRITOS (varios por municipio, como debe ser)
-- ----------------------------------------------------------------
create view delegados.portal_distritos as
select u.municipio_id, u.jce_id, u.nombre, u.es_dm,
       count(distinct c.id_colegio)              as colegios,
       count(distinct c.id_recinto)              as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct c.id_colegio) * 3          as meta
from delegados._unidades_jce u
left join public.jce_colegio c on c.id_municipio = u.jce_id
group by u.municipio_id, u.jce_id, u.nombre, u.es_dm;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

-- ----------------------------------------------------------------
-- 4. CIRCUNSCRIPCIONES por municipio
-- ----------------------------------------------------------------
create view delegados.portal_circunscripciones as
select u.municipio_id,
       ci.id::integer                             as circ_id,
       coalesce(nullif(trim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct c.id_colegio)               as colegios,
       count(distinct c.id_colegio) * 3           as meta
from delegados._unidades_jce u
join public.jce_colegio c          on c.id_municipio = u.jce_id
join public.jce_recinto rc         on rc.id = c.id_recinto
join public.jce_circunscripcion ci on ci.id = rc.id_circunscripcion
group by u.municipio_id, ci.id, ci.descripcion, ci.codigo_circunscripcion;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
-- 5. COBERTURA POR COLEGIO (distrito + circunscripción)
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
  select u.nombre,
         u.jce_id,
         coalesce(nullif(trim(ci.descripcion),''), 'Circ. ' || ci.codigo_circunscripcion, '—')::text,
         ci.id::integer,
         c.id_colegio::integer,
         coalesce(nullif(trim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion::text,'—')::text,
         coalesce(rc.direccion::text,'')::text,
         coalesce(sum(distinct c.cantidad_inscritos),0)::bigint,
         count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
    from delegados._unidades_jce u
    join public.jce_colegio c on c.id_municipio = u.jce_id
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join public.jce_circunscripcion ci on ci.id = rc.id_circunscripcion
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where u.municipio_id = p_municipio
     and (p_jce  is null or u.jce_id = p_jce)
     and (p_circ is null or ci.id = p_circ)
   group by u.nombre, u.jce_id, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
            c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by u.es_dm, u.nombre, coalesce(rc.descripcion,''), 6;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------
-- 6. AVANCE POR DISTRITO
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
    select u.jce_id as jce, u.nombre, u.es_dm, c.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as n
      from delegados._unidades_jce u
      join public.jce_colegio c on c.id_municipio = u.jce_id
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                  and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
       and (v_dist is null or u.jce_id = v_dist)
     group by u.jce_id, u.nombre, u.es_dm, c.id_colegio
  )
  select cole.jce, cole.nombre, cole.es_dm,
         count(*)::bigint,
         (count(*) * 3)::bigint,
         coalesce(sum(cole.n), 0)::bigint,
         count(*) filter (where cole.n >= 3)::bigint,
         count(*) filter (where cole.n > 0 and cole.n < 3)::bigint,
         count(*) filter (where cole.n = 0)::bigint
    from cole
   group by cole.jce, cole.nombre, cole.es_dm
   order by cole.es_dm, cole.nombre;
end $$;

revoke all on function delegados.portal_kpi_distritos(integer) from public, anon;
grant execute on function delegados.portal_kpi_distritos(integer) to authenticated;

-- ----------------------------------------------------------------
-- 7. COBERTURA RESUMEN (por municipio, con todos sus distritos)
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
    select v2.municipio_id
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (
         v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and v2.municipio_id = portal_mun())
         or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
       )
  ),
  cole as (
    select a.municipio_id as mun_id, c.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as personas
      from alcance a
      join delegados._unidades_jce u on u.municipio_id = a.municipio_id
      join public.jce_colegio c      on c.id_municipio = u.jce_id
      left join postulantes_2028 p   on p.id_colegio_padron = c.id_colegio
                                    and p.municipio_id = a.municipio_id
     group by a.municipio_id, c.id_colegio
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
-- 8. DIAGNÓSTICO ampliado
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'municipios',        (select count(*) from portal_metas_municipio),
    'regiones',          (select count(distinct macroregion) from portal_metas_municipio),
    'meta_nacional',     (select sum(meta) from portal_metas_municipio where estatus is null or estatus <> 'I'),
    'unidades_jce',      (select count(*) from delegados._unidades_jce),
    'distritos',         (select count(*) from portal_distritos),
    'distritos_dm',      (select count(*) from portal_distritos where es_dm),
    'muns_con_varios',   (select count(*) from (select municipio_id from portal_distritos
                                                 group by municipio_id having count(*) > 1) x),
    'circunscripciones', (select count(*) from portal_circunscripciones),
    'ejemplo_multi',     (select jsonb_build_object('municipio', v.nombre, 'municipio_id', v.municipio_id,
                                                    'distritos', x.n, 'meta', v.meta)
                            from (select municipio_id, count(*) n from portal_distritos
                                   group by municipio_id order by n desc limit 1) x
                            join portal_metas_municipio v on v.municipio_id = x.municipio_id),
    -- ESTRUCTURA CRUDA (para saber qué ruta funciona en esta base):
    'estructura', jsonb_build_object(
      'jce_municipio_total',    (select count(*) from public.jce_municipio),
      'jce_sin_padre',          (select count(*) from public.jce_municipio where id_municipio_padre is null),
      'jce_padre_si_mismo',     (select count(*) from public.jce_municipio where id_municipio_padre = id),
      'jce_padre_distinto',     (select count(*) from public.jce_municipio
                                  where id_municipio_padre is not null and id_municipio_padre <> id),
      'jce_marcados_dm',        (select count(*) from public.jce_municipio
                                  where upper(trim(coalesce(dm::text,''))) in ('S','SI','1','T','TRUE','Y','V','D')),
      'mapeo_filas',            (select count(*) from public._mapeo_municipio),
      'mapeo_validas',          (select count(*) from public._mapeo_municipio mm
                                   join public.municipios m on m.id = mm.id_actual),
      'ciudad_seccion_pares',   (select count(distinct (id_municipio, id_distrito_municipal))
                                   from public.jce_ciudad_seccion where id_distrito_municipal is not null),
      'colegios_total',         (select count(*) from public.jce_colegio),
      'colegios_alcanzados',    (select count(distinct c.id_colegio) from public.jce_colegio c
                                   join delegados._unidades_jce u on u.jce_id = c.id_municipio)
    )
  );
$$;

revoke all on function delegados.portal_diag() from public, anon;
grant execute on function delegados.portal_diag() to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--   select jsonb_pretty(delegados.portal_diag());
--   Esperado: muns_con_varios > 100 · meta_nacional ≈ 51,981 · ejemplo_multi con varios distritos
