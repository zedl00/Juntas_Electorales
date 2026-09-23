-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 14
--  SEPARACIÓN CORRECTA DEL EXTERIOR (OCLEE) Y CIRCUNSCRIPCIONES REALES
-- ----------------------------------------------------------------
--  PROBLEMA CORREGIDO:
--   · Las OCLEE se estaban resolviendo por la jerarquía nacional
--     (jce_municipio → distritos municipales), lo que hacía que una
--     oficina del exterior heredara distritos dominicanos
--     (ej.: Barcelona mostrando «Los Fríos (DM)» y sus colegios).
--     El exterior tiene su propia tabla: jce_oclee.
--   · Las circunscripciones aparecían en todos los municipios aunque
--     la demarcación no esté dividida. Ahora solo se consideran las
--     divisiones reales (más de una circunscripción en el municipio).
--
--  NO se crea ninguna tabla nueva ni se modifica ninguna del SNE:
--  todo son vistas dentro del esquema «delegados». La estructura JCE
--  se mantiene intacta para futuras cargas de datos.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Idempotente.
--  Requiere fase11 (o posterior) ya ejecutada.
-- ================================================================

set search_path = delegados, public;

drop view if exists delegados.portal_circunscripciones cascade;
drop view if exists delegados.portal_distritos cascade;
drop view if exists delegados.portal_metas_municipio cascade;
drop view if exists delegados._unidades_jce cascade;

-- ----------------------------------------------------------------
-- 1. UNIDADES: el exterior NO hereda jerarquía nacional
-- ----------------------------------------------------------------
create view delegados._unidades_jce as
with mapeo as (
  select distinct on (mm.id_jce)
         mm.id_jce::integer as jce_id, mm.id_actual::integer as municipio_id
    from public._mapeo_municipio mm
    join public.municipios m on m.id = mm.id_actual
   where coalesce(m.tipo,'') <> 'OCLEE'          -- ← el exterior se resuelve aparte
   order by mm.id_jce, (mm.id_actual = mm.id_jce) desc, mm.id_actual
),
cand as (
  select jm.id::integer as jce_id, mp.municipio_id, 1 as prio
    from public.jce_municipio jm join mapeo mp on mp.jce_id = jm.id
  union all
  select jm.id::integer, mp.municipio_id, 2
    from public.jce_municipio jm
    join mapeo mp on mp.jce_id = coalesce(jm.id_municipio_padre, jm.id)
  union all
  select jm.id::integer, m.id::integer, 3
    from public.jce_municipio jm
    join public.municipios m on m.id = jm.id
   where coalesce(m.tipo,'') <> 'OCLEE'
  union all
  select jm.id::integer, m.id::integer, 4
    from public.jce_municipio jm
    join public.municipios m on m.id = coalesce(jm.id_municipio_padre, jm.id)
   where coalesce(m.tipo,'') <> 'OCLEE'
)
select distinct on (cand.jce_id)
       cand.municipio_id,
       cand.jce_id,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text as nombre,
       (jm.id_municipio_padre is not null and jm.id_municipio_padre <> jm.id) as es_dm
  from cand
  join public.jce_municipio jm on jm.id = cand.jce_id
 order by cand.jce_id, cand.prio;

alter view delegados._unidades_jce owner to postgres;
grant select on delegados._unidades_jce to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. EXTERIOR: cada OCLEE con sus colegios, desde jce_oclee
--    Enlace por nombre normalizado (sin acentos ni mayúsculas), que
--    es como están escritas las oficinas en ambas tablas.
-- ----------------------------------------------------------------
create or replace function delegados._norm(t text) returns text
language sql immutable as $$
  select upper(trim(regexp_replace(
    translate(coalesce(t,''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'),
    '\s+', ' ', 'g')))
$$;

drop view if exists delegados._unidades_oclee cascade;
create view delegados._unidades_oclee as
select m.id::integer            as municipio_id,
       o.id::integer            as oclee_id,
       o.id_municipio::integer  as jce_id,
       o.id_circunscripcion::integer as circ_id,
       initcap(lower(o.descripcion))::text as nombre
  from public.municipios m
  join public.jce_oclee o
    on delegados._norm(o.descripcion) = delegados._norm(m.nombre)
 where coalesce(m.tipo,'') = 'OCLEE';

alter view delegados._unidades_oclee owner to postgres;
grant select on delegados._unidades_oclee to authenticated, service_role;

-- Colegios del exterior: los que pertenecen a la demarcación JCE de la
-- oficina Y a su circunscripción exterior (evita mezclar oficinas).
drop view if exists delegados._colegio_oclee cascade;
create view delegados._colegio_oclee as
select u.municipio_id, u.oclee_id, c.id_colegio::integer, c.id_recinto::integer, u.circ_id
  from delegados._unidades_oclee u
  join public.jce_colegio c on c.id_municipio = u.jce_id
  left join public.jce_recinto rc on rc.id = c.id_recinto
 where rc.id_circunscripcion is null or rc.id_circunscripcion = u.circ_id;

alter view delegados._colegio_oclee owner to postgres;
grant select on delegados._colegio_oclee to authenticated, service_role;

-- ----------------------------------------------------------------
-- 3. METAS: nacional por unidades JCE, exterior por OCLEE
-- ----------------------------------------------------------------
create view delegados.portal_metas_municipio as
with col_nac as (
  select u.municipio_id, cd.id_colegio, cd.id_recinto
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
),
col_ext as (
  select municipio_id, id_colegio, id_recinto from delegados._colegio_oclee
),
col as (
  select municipio_id, id_colegio, id_recinto from col_nac
  union all
  select municipio_id, id_colegio, id_recinto from col_ext
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
       coalesce(sum(distinct c2.cantidad_inscritos), 0) as electores,
       count(distinct col.id_colegio) * 3         as meta,
       (m.id_municipio_padre is not null)         as es_dm,
       m.id_municipio_padre                       as municipio_padre_id,
       m.tipo                                     as provincia_tipo
from public.municipios m
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join col on col.municipio_id = m.id
left join public.jce_colegio c2 on c2.id_colegio = col.id_colegio
group by m.id, p.macroregion, p.nombre, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 4. DISTRITOS: solo territorio nacional (el exterior no tiene)
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
-- 5. CIRCUNSCRIPCIONES: solo divisiones REALES
--    (un municipio con una sola circunscripción no está dividido)
-- ----------------------------------------------------------------
create view delegados.portal_circunscripciones as
with base as (
  select u.municipio_id, ci.id::integer as circ_id,
         coalesce(nullif(trim(ci.descripcion),''),
                  'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
         count(distinct cd.id_colegio) as colegios
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
    join public.jce_circunscripcion ci  on ci.id = cd.circ_id
   group by u.municipio_id, ci.id, ci.descripcion, ci.codigo_circunscripcion
),
divididos as (
  select municipio_id from base group by municipio_id having count(*) > 1
)
select b.municipio_id, b.circ_id, b.nombre, b.colegios, b.colegios * 3 as meta
  from base b join divididos d on d.municipio_id = b.municipio_id;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
-- 6. COBERTURA: nacional y exterior por el mismo RPC
-- ----------------------------------------------------------------
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
  v_prov integer; v_reg text; v_tipo text;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;
  select v2.provincia_id, v2.macroregion, v2.tipo into v_prov, v_reg, v_tipo
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

  if coalesce(v_tipo,'') = 'OCLEE' then
    return query
    select u.nombre, u.jce_id,
           coalesce(nullif(trim(ci.descripcion),''), '—')::text, ci.id::integer,
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
      from delegados._unidades_oclee u
      join delegados._colegio_oclee co on co.municipio_id = u.municipio_id and co.oclee_id = u.oclee_id
      join public.jce_colegio c on c.id_colegio = co.id_colegio
      left join public.jce_recinto rc on rc.id = c.id_recinto
      left join public.jce_circunscripcion ci on ci.id = u.circ_id
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
     group by u.nombre, u.jce_id, ci.id, ci.descripcion,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by 7, 6;
  else
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
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
       and (p_jce  is null or u.jce_id = p_jce)
       and (p_circ is null or cd.circ_id = p_circ)
     group by u.nombre, u.jce_id, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by u.es_dm, u.nombre, coalesce(rc.descripcion,''), 6;
  end if;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------
-- 7. RESUMEN por municipio (nacional + exterior)
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
  todos as (
    select u.municipio_id, cd.id_colegio
      from delegados._unidades_jce u
      join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
    union all
    select municipio_id, id_colegio from delegados._colegio_oclee
  ),
  cole as (
    select a.municipio_id as mun_id, t.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as personas
      from alcance a
      join todos t on t.municipio_id = a.municipio_id
      left join postulantes_2028 p on p.id_colegio_padron = t.id_colegio
                                  and p.municipio_id = a.municipio_id
     group by a.municipio_id, t.id_colegio
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
-- 8. DIAGNÓSTICO del exterior y las circunscripciones
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag_oclee() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'oclee_en_jce',        (select count(*) from public.jce_oclee),
    'oclee_en_app',        (select count(*) from public.municipios where coalesce(tipo,'') = 'OCLEE'),
    'oclee_enlazadas',     (select count(*) from delegados._unidades_oclee),
    'oclee_sin_enlace',    (select jsonb_agg(m.nombre order by m.nombre)
                              from public.municipios m
                             where coalesce(m.tipo,'') = 'OCLEE'
                               and not exists (select 1 from delegados._unidades_oclee u
                                                where u.municipio_id = m.id)),
    'colegios_exterior',   (select count(distinct id_colegio) from delegados._colegio_oclee),
    'muestra_oclee',       (select jsonb_agg(x) from (
                              select jsonb_build_object('oficina', u.nombre, 'jce_id', u.jce_id,
                                       'circ_id', u.circ_id,
                                       'colegios', (select count(*) from delegados._colegio_oclee co
                                                     where co.oclee_id = u.oclee_id)) as x
                                from delegados._unidades_oclee u order by u.nombre limit 8) y),
    'muns_divididos_circ', (select count(distinct municipio_id) from portal_circunscripciones),
    'muestra_circ',        (select jsonb_agg(x) from (
                              select jsonb_build_object('municipio', v.nombre, 'circunscripciones', c.n) as x
                                from (select municipio_id, count(*) n from portal_circunscripciones
                                       group by municipio_id order by n desc limit 6) c
                                join portal_metas_municipio v on v.municipio_id = c.municipio_id) y),
    'meta_nacional',       (select sum(meta) from portal_metas_municipio
                             where (estatus is null or estatus <> 'I') and coalesce(tipo,'') <> 'OCLEE'),
    'meta_exterior',       (select sum(meta) from portal_metas_municipio where coalesce(tipo,'') = 'OCLEE')
  );
$$;

revoke all on function delegados.portal_diag_oclee() from public, anon;
grant execute on function delegados.portal_diag_oclee() to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  select jsonb_pretty(delegados.portal_diag_oclee());
