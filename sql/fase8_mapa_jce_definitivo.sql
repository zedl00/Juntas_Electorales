-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 8 · MAPA JCE DEFINITIVO
-- ----------------------------------------------------------------
--  DIAGNÓSTICO QUE RESUELVE:
--   · _mapeo_municipio es 1:1 (384 filas, 384 id_actual distintos):
--     NO pliega los distritos municipales bajo su municipio. Por eso
--     ningún municipio mostraba distritos y la meta daba 49,728 en
--     lugar de 51,981 (faltaban los 751 colegios de los DM).
--   · jce_municipio.id_municipio_padre apunta a sí mismo en las
--     cabeceras → todo salía marcado como DM.
--  SOLUCIÓN: vista portal_mapa_jce que asocia cada municipio de la
--  aplicación con TODAS sus demarcaciones JCE (cabecera + DMs),
--  derivando la jerarquía de jce_municipio. Todo lo demás se apoya
--  en ella. Ejecutar DESPUÉS de fase1, fase2, fase5 y fase7.
--  Idempotente. Reemplaza lo territorial de fase3/4/6/7.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. MAPA MAESTRO: municipio de la app ↔ demarcaciones JCE
-- ----------------------------------------------------------------
drop view if exists delegados.portal_mapa_jce cascade;
create view delegados.portal_mapa_jce as
with cab as (   -- filas del mapeo que sí corresponden a un municipio de la app
  select mm.id_actual::integer as municipio_id, mm.id_jce::integer as jce_id
    from public._mapeo_municipio mm
    join public.municipios m on m.id = mm.id_actual
),
jm as (         -- cada demarcación JCE con su cabecera real
  select j.id::integer                                                as jce_id,
         coalesce(nullif(j.id_municipio_padre, j.id), j.id)::integer  as jce_cab,
         j.descripcion,
         (j.id_municipio_padre is not null and j.id_municipio_padre <> j.id)
           or upper(trim(coalesce(j.dm::text,''))) in ('S','SI','1','T','TRUE','Y','V','D') as es_dm
    from public.jce_municipio j
)
select distinct municipio_id, jce_id, nombre, es_dm from (
  -- a) mapeo directo (cubre el caso en que el mapeo ya plegara los DM)
  select c.municipio_id, j.jce_id,
         initcap(lower(coalesce(j.descripcion, 'Demarcación ' || j.jce_id)))::text as nombre,
         j.es_dm
    from cab c join jm j on j.jce_id = c.jce_id
  union
  -- b) jerarquía JCE: todas las demarcaciones cuya cabecera es la del municipio
  select c.municipio_id, j.jce_id,
         initcap(lower(coalesce(j.descripcion, 'Demarcación ' || j.jce_id)))::text,
         j.es_dm
    from cab c join jm j on j.jce_cab = c.jce_id
) t;

alter view delegados.portal_mapa_jce owner to postgres;
revoke all on delegados.portal_mapa_jce from anon;
grant select on delegados.portal_mapa_jce to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. METAS POR MUNICIPIO (ahora incluyen los colegios de los DM)
-- ----------------------------------------------------------------
create or replace view delegados.portal_metas_municipio as
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
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join delegados.portal_mapa_jce u on u.municipio_id = m.id
left join public.jce_colegio c on c.id_municipio = u.jce_id
group by m.id, p.macroregion, p.nombre, p.tipo, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 3. DISTRITOS y CIRCUNSCRIPCIONES sobre el mapa maestro
-- ----------------------------------------------------------------
drop view if exists delegados.portal_distritos;
create view delegados.portal_distritos as
select u.municipio_id, u.jce_id, u.nombre, u.es_dm,
       count(distinct c.id_colegio)           as colegios,
       count(distinct c.id_recinto)           as recintos,
       coalesce(sum(c.cantidad_inscritos), 0) as electores,
       count(distinct c.id_colegio) * 3       as meta
from delegados.portal_mapa_jce u
left join public.jce_colegio c on c.id_municipio = u.jce_id
group by u.municipio_id, u.jce_id, u.nombre, u.es_dm;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

drop function if exists delegados.portal_circunscripciones();
drop function if exists delegados.portal_circunscripciones(integer);
drop view if exists delegados.portal_circunscripciones;
create view delegados.portal_circunscripciones as
select u.municipio_id,
       ci.id::integer as circ_id,
       coalesce(nullif(trim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct c.id_colegio)     as colegios,
       count(distinct c.id_colegio) * 3 as meta
from delegados.portal_mapa_jce u
join public.jce_colegio c          on c.id_municipio = u.jce_id
join public.jce_recinto rc         on rc.id = c.id_recinto
join public.jce_circunscripcion ci on ci.id = rc.id_circunscripcion
group by u.municipio_id, ci.id, ci.descripcion, ci.codigo_circunscripcion;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
-- 4. COBERTURA POR COLEGIO (distrito + circunscripción)
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
    from delegados.portal_mapa_jce u
    join public.jce_colegio c on c.id_municipio = u.jce_id
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join public.jce_circunscripcion ci on ci.id = rc.id_circunscripcion
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where u.municipio_id = p_municipio
     and (p_jce  is null or u.jce_id = p_jce)
     and (p_circ is null or ci.id = p_circ)
   group by u.jce_id, u.nombre, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
            c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by u.es_dm, 1, 7, 6;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------
-- 5. AVANCE POR DISTRITO y COBERTURA RESUMEN
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
      from delegados.portal_mapa_jce u
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
      join delegados.portal_mapa_jce u on u.municipio_id = a.municipio_id
      join public.jce_colegio c on c.id_municipio = u.jce_id
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
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
-- 6. BÚSQUEDA EN PADRÓN: quien vota en un DM pertenece a su municipio
-- ----------------------------------------------------------------
create or replace function delegados.portal_municipio_de_jce(p_jce integer)
returns integer language sql stable security definer set search_path = delegados, public as
$$ select u.municipio_id from delegados.portal_mapa_jce u where u.jce_id = p_jce limit 1 $$;

grant execute on function delegados.portal_municipio_de_jce(integer) to authenticated, service_role;

-- ----------------------------------------------------------------
-- 7. DIAGNÓSTICO ESTRUCTURAL AMPLIADO
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'municipios',        (select count(*) from portal_metas_municipio),
    'regiones',          (select count(distinct macroregion) from portal_metas_municipio),
    'mapeo_filas',       (select count(*) from public._mapeo_municipio),
    'jce_municipios',    (select count(*) from public.jce_municipio),
    'demarcaciones',     (select count(*) from portal_mapa_jce),
    'demarcaciones_dm',  (select count(*) from portal_mapa_jce where es_dm),
    'muns_con_varios',   (select count(*) from (select municipio_id from portal_mapa_jce
                                                 group by municipio_id having count(*) > 1) x),
    'circunscripciones', (select count(*) from portal_circunscripciones),
    'meta_nacional',     (select sum(meta) from portal_metas_municipio where estatus is null or estatus <> 'I'),
    'colegios_total',    (select sum(colegios) from portal_metas_municipio where estatus is null or estatus <> 'I'),
    'colegios_huerfanos',(select count(*) from public.jce_colegio c
                           where not exists (select 1 from portal_mapa_jce u where u.jce_id = c.id_municipio)),
    'top_distritos',     (select jsonb_agg(jsonb_build_object('municipio', v.nombre, 'municipio_id', x.municipio_id, 'distritos', x.n) order by x.n desc)
                            from (select municipio_id, count(*) n from portal_mapa_jce
                                   group by municipio_id order by n desc limit 5) x
                            join portal_metas_municipio v on v.municipio_id = x.municipio_id)
  );
$$;

revoke all on function delegados.portal_diag() from public, anon;
grant execute on function delegados.portal_diag() to authenticated;

-- ----------------------------------------------------------------
-- 8. BÚSQUEDA EN PADRÓN sobre el mapa maestro
--    (quien vota en un DM se registra en su municipio, sin falsa
--     alerta de demarcación)
-- ----------------------------------------------------------------

create or replace function delegados.portal_buscar_cedula(p_ced text) returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare
  v_ced text := regexp_replace(coalesce(p_ced,''), '\D', '', 'g');
  v_fmt text;
  r record;
  v_mun_app integer;
  v_mun_app_nombre text;
  v_exp integer := 0;
  v_post record;
  v_es_usuario boolean := false;
begin
  if portal_rol() is null then
    raise exception 'Acceso no autorizado';
  end if;
  if length(v_ced) < 8 then
    return jsonb_build_object('encontrado', false, 'error', 'Cédula incompleta');
  end if;

  select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
         pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
         pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
         pa.id_municipio,
         c.descripcion  as colegio_desc,
         rc.descripcion as recinto_desc,
         rc.direccion   as recinto_dir,
         jm.descripcion as jce_municipio
    into r
    from jce_padron pa
    left join jce_colegio  c  on c.id_colegio = pa.id_colegio
    left join jce_recinto  rc on rc.id = c.id_recinto
    left join jce_municipio jm on jm.id = pa.id_municipio
   where pa.cedula = v_ced and pa.activo
   limit 1;

  if not found and length(v_ced) = 11 then
    v_fmt := substr(v_ced,1,3) || '-' || substr(v_ced,4,7) || '-' || substr(v_ced,11,1);
    select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
           pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
           pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
           pa.id_municipio,
           c.descripcion  as colegio_desc,
           rc.descripcion as recinto_desc,
           rc.direccion   as recinto_dir,
           jm.descripcion as jce_municipio
      into r
      from jce_padron pa
      left join jce_colegio  c  on c.id_colegio = pa.id_colegio
      left join jce_recinto  rc on rc.id = c.id_recinto
      left join jce_municipio jm on jm.id = pa.id_municipio
     where pa.cedula = v_fmt and pa.activo
     limit 1;
  end if;

  perform portal_log('consulta_padron', 'cedula', v_ced,
                     jsonb_build_object('encontrado', found));

  if not found then
    return jsonb_build_object('encontrado', false);
  end if;

  -- El municipio de la app se resuelve por el mapa maestro: quien vota en un
  -- distrito municipal pertenece al municipio que lo contiene.
  select u.municipio_id into v_mun_app
    from delegados.portal_mapa_jce u where u.jce_id = r.id_municipio limit 1;
  if v_mun_app is not null then
    select nombre into v_mun_app_nombre from municipios where id = v_mun_app;
  end if;

  begin
    select count(*) into v_exp
      from historial_delegado h
     where regexp_replace(coalesce(h.cedula,''), '\D', '', 'g') = v_ced;
  exception when undefined_table or undefined_column then
    v_exp := 0;
  end;

  select numero_formulario, estado, municipio_id into v_post
    from postulantes_2028
   where cedula = v_ced limit 1;

  select exists(
    select 1 from usuarios_territoriales
     where regexp_replace(cedula, '\D', '', 'g') = v_ced
  ) into v_es_usuario;

  return jsonb_build_object(
    'encontrado', true,
    'cedula', v_ced,
    'nombres', r.nombres,
    'apellido1', r.apellido1,
    'apellido2', r.apellido2,
    'sexo', r.id_sexo,
    'fecha_nacimiento', r.fecha_nacimiento,
    'lugar_votacion', r.lugar_votacion,
    'id_colegio', r.id_colegio,
    'codigo_colegio', r.codigo_colegio,
    'colegio_desc', r.colegio_desc,
    'codigo_recinto', r.codigo_recinto,
    'recinto', r.recinto_desc,
    'recinto_dir', r.recinto_dir,
    'circunscripcion', r.codigo_circunscripcion,
    'jce_municipio', r.jce_municipio,
    'municipio_app_id', v_mun_app,
    'municipio_app', v_mun_app_nombre,
    'experiencia_2024', v_exp > 0,
    'experiencia_veces', v_exp,
    'ya_postulado', v_post.numero_formulario is not null,
    'postulado_numero', v_post.numero_formulario,
    'postulado_estado', v_post.estado,
    'postulado_municipio_id', v_post.municipio_id,
    'es_usuario', v_es_usuario
  );
end $$;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--   select jsonb_pretty(delegados.portal_diag());
--   → meta_nacional debe dar 51,981 y muns_con_varios > 0
