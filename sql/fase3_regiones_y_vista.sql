-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 3a · REGIONES CONFIABLES,
--  DISTRITOS EN LA VISTA Y ALCANCES ALINEADOS
-- ----------------------------------------------------------------
--  · Ejecutar DESPUÉS de fase1 y fase2. Idempotente.
--  · Problema que resuelve: municipios.macroregion puede estar
--    vacío → el filtro de Región salía en blanco. Ahora la región
--    se deriva de la estructura JCE:
--      provincias.region_id → jce_region → (jce_macroregion)
--    sin modificar ninguna tabla del SNE.
--  · Además la vista expone es_dm y municipio_padre_id para el
--    encadenamiento Municipio → Distrito Municipal en los filtros.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. VISTA DE METAS con región derivada + jerarquía de distritos
--    (mismas columnas de siempre + 2 nuevas al final)
-- ----------------------------------------------------------------

create or replace view delegados.portal_metas_municipio as
select m.id            as municipio_id,
       m.nombre,
       m.provincia_id,
       m.provincia_nombre,
       coalesce(
         nullif(trim(m.macroregion), ''),
         nullif(trim(p.macroregion), ''),
         jr.descripcion::text,
         'Sin región'
       )                                          as macroregion,
       m.tipo,
       m.estatus,
       count(distinct c.id_colegio)               as colegios,
       count(distinct c.id_recinto)               as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)     as electores,
       count(distinct c.id_colegio) * 3           as meta,
       (m.id_municipio_padre is not null)         as es_dm,
       m.id_municipio_padre                       as municipio_padre_id
from public.municipios m
left join public.provincias p        on p.id = m.provincia_id
left join public.jce_region jr       on jr.id = p.region_id
left join public._mapeo_municipio mm on mm.id_actual = m.id
left join public.jce_colegio c       on c.id_municipio = mm.id_jce
group by m.id, p.macroregion, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. PERFIL: la región del usuario sale de la misma derivación
--    (conserva el registro de acceso de la Fase 2)
-- ----------------------------------------------------------------

create or replace function delegados.portal_mi_perfil() returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v jsonb;
begin
  update usuarios_territoriales set ultimo_acceso = now() where id = auth.uid();

  select jsonb_build_object(
    'id', u.id, 'cedula', u.cedula, 'nombre', u.nombre, 'telefono', u.telefono,
    'rol', u.rol, 'activo', u.activo, 'primer_acceso', u.primer_acceso,
    'acuse_instructivo', u.acuse_instructivo,
    'municipio_id', u.municipio_id,
    'municipio', m.nombre,
    'junta', m.junta_nombre,
    'tipo_territorio', m.tipo,
    'provincia_id', coalesce(u.provincia_id, m.provincia_id),
    'provincia', coalesce(p.nombre, m.provincia_nombre),
    'region', coalesce(u.region, v2.macroregion),
    'colegios', v2.colegios, 'meta', v2.meta, 'electores', v2.electores
  ) into v
  from usuarios_territoriales u
  left join municipios m  on m.id = u.municipio_id
  left join provincias p  on p.id = coalesce(u.provincia_id, m.provincia_id)
  left join portal_metas_municipio v2 on v2.municipio_id = u.municipio_id
  where u.id = auth.uid();

  if v is not null then
    perform portal_log('acceso', 'sesion', null, jsonb_build_object('rol', v->>'rol'));
  end if;
  return v;
end $$;

-- ----------------------------------------------------------------
-- 3. COBERTURA: el alcance regional usa la región derivada
--    (mismas firmas; solo cambia la fuente del filtro)
-- ----------------------------------------------------------------

create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;

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
      join public._mapeo_municipio mm on mm.id_actual = a.municipio_id
      join public.jce_colegio c       on c.id_municipio = mm.id_jce
      left join postulantes_2028 p    on p.id_colegio_padron = c.id_colegio
                                     and p.municipio_id = a.municipio_id
     group by a.municipio_id, c.id_colegio
  )
  select cole.mun_id,
         count(*)::bigint,
         count(*) filter (where personas >= 3),
         count(*) filter (where personas > 0 and personas < 3),
         count(*) filter (where personas = 0)
    from cole
   group by cole.mun_id;
end $$;

create or replace function delegados.portal_cobertura_colegios(p_municipio integer)
returns table (
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
  select c.id_colegio,
         coalesce(c.descripcion,'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion,'—')::text,
         coalesce(rc.direccion,'')::text,
         coalesce(sum(distinct c.cantidad_inscritos),0)::bigint,
         count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
    from public._mapeo_municipio mm
    join public.jce_colegio c  on c.id_municipio = mm.id_jce
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where mm.id_actual = p_municipio
   group by c.id_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by rc.descripcion, c.descripcion;
end $$;

notify pgrst, 'reload schema';

-- Verificación (opcional):
--   select macroregion, count(*) from delegados.portal_metas_municipio group by 1 order by 2 desc;
--   → deben aparecer las regiones (ya no en blanco).
