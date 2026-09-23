-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 6 · CIERRE DEFINITIVO
-- ----------------------------------------------------------------
--  Un solo script que CONVERGE el estado correcto sin importar qué
--  versión de fase4 se ejecutó antes. Idempotente. Corrige:
--   A) Tipos reales JCE (smallint) → "structure of query does not
--      match function result type" al abrir cobertura/OCLEE.
--   B) Provincia/Región vacías en la vista (nombres desde tablas
--      provincias/jce_region, como el sistema SNE que funciona).
--   C) Postulantes sin provincia/región guardada → el filtro de
--      Provincia en Postulantes no encontraba registros. Se agrega
--      trigger de georreferencia + relleno de los ya registrados.
-- ================================================================

set search_path = delegados, public;

-- ── A+B · Vista de metas (región y provincia desde las fuentes reales) ──
create or replace view delegados.portal_metas_municipio as
select m.id            as municipio_id,
       m.nombre,
       m.provincia_id,
       coalesce(nullif(trim(m.provincia_nombre), ''), p.nombre) as provincia_nombre,
       case when m.tipo = 'OCLEE' then 'Exterior'
            else coalesce(
              nullif(trim(p.macroregion), ''),
              nullif(trim(m.macroregion), ''),
              jr.descripcion::text,
              'Sin región'
            )
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
left join public.provincias p        on p.id = m.provincia_id
left join public.jce_region jr       on jr.id = p.region_id
left join public._mapeo_municipio mm on mm.id_actual = m.id
left join public.jce_colegio c       on c.id_municipio = mm.id_jce
group by m.id, p.macroregion, p.nombre, p.tipo, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ── A · Distritos con tipos normalizados ──
-- (drop primero: si la vista existe de una fase anterior con jce_id smallint,
--  PostgreSQL no permite cambiarle el tipo con create or replace)
drop view if exists delegados.portal_distritos;
create view delegados.portal_distritos as
select mm.id_actual::integer                     as municipio_id,
       jm.id::integer                            as jce_id,
       initcap(lower(coalesce(jm.descripcion, 'Demarcación ' || jm.id)))::text as nombre,
       (jm.id_municipio_padre is not null
         or upper(trim(coalesce(jm.dm::text,''))) in ('S','SI','1','T','TRUE','Y','V','D')) as es_dm,
       count(distinct c.id_colegio)              as colegios,
       count(distinct c.id_recinto)              as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct c.id_colegio) * 3          as meta
from public._mapeo_municipio mm
join public.jce_municipio jm on jm.id = mm.id_jce
left join public.jce_colegio c on c.id_municipio = jm.id
group by mm.id_actual, jm.id, jm.descripcion, jm.dm, jm.id_municipio_padre;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

-- ── A · Cobertura por colegio: TODOS los tipos casteados ──
drop function if exists delegados.portal_cobertura_colegios(integer);
create or replace function delegados.portal_cobertura_colegios(p_municipio integer, p_jce integer default null)
returns table (
  distrito text, jce_id integer,
  id_colegio integer, colegio text, recinto text, recinto_dir text,
  inscritos bigint, titulares bigint, suplentes bigint, observadores bigint,
  indistintos bigint, personas bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
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
  select initcap(lower(coalesce(jm.descripcion, '—')))::text,
         jm.id::integer,
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
    from public._mapeo_municipio mm
    join public.jce_municipio jm on jm.id = mm.id_jce
    join public.jce_colegio c    on c.id_municipio = jm.id
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where mm.id_actual = p_municipio
     and (p_jce is null or jm.id = p_jce)
   group by jm.id, jm.descripcion, c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by 1, 5, 4;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer) to authenticated;

-- ── C · Georreferencia automática del postulante + relleno histórico ──
create or replace function delegados.trg_p28_geo() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  select v.provincia_id, v.macroregion into new.provincia_id, new.macroregion
    from portal_metas_municipio v where v.municipio_id = new.municipio_id;
  return new;
end $$;

drop trigger if exists p28_geo on delegados.postulantes_2028;
create trigger p28_geo
before insert or update of municipio_id on delegados.postulantes_2028
for each row execute function delegados.trg_p28_geo();

update delegados.postulantes_2028 p
   set provincia_id = v.provincia_id,
       macroregion  = v.macroregion
  from delegados.portal_metas_municipio v
 where v.municipio_id = p.municipio_id
   and (p.provincia_id is distinct from v.provincia_id
     or p.macroregion  is distinct from v.macroregion);

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN (los 3 resultados que confirman el cierre) ──
-- select macroregion, count(*), sum(meta) from delegados.portal_metas_municipio group by 1 order by 3 desc;
-- select provincia_nombre, count(*) from delegados.portal_metas_municipio where provincia_tipo is distinct from 'OCLEE' group by 1 order by 1 limit 8;
-- select count(*) as postulantes_sin_provincia from delegados.postulantes_2028 where provincia_id is null;
