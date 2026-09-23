-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 20
--  EL ALCANCE DE DISTRITO MANDA EN TODOS LOS INDICADORES
-- ----------------------------------------------------------------
--  PROBLEMA: un usuario asignado a un distrito veía la meta y los
--  colegios del MUNICIPIO completo (San Juan 807) en lugar de los
--  de su distrito (Pedro Corto 39). El conteo de postulantes sí
--  respetaba el distrito, pero la meta se calculaba sobre el
--  municipio, dando un avance falso.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase19.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. PERFIL: meta, colegios y electores del distrito cuando aplica
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
    'ver_distritos', u.ver_distritos,
    'puede_registrar', coalesce(u.puede_registrar, u.rol in ('enc_electoral','admin_sne')),
    'municipio_id', u.municipio_id, 'municipio', m.nombre,
    'jce_id', u.jce_id, 'distrito', d.nombre,
    'junta', m.junta_nombre, 'tipo_territorio', m.tipo,
    'provincia_id', coalesce(u.provincia_id, m.provincia_id),
    'provincia', coalesce(p.nombre, m.provincia_nombre),
    'region', coalesce(u.region, v2.macroregion),
    -- si tiene distrito asignado, sus cifras son las del distrito
    'colegios', coalesce(d.colegios, v2.colegios),
    'meta', coalesce(d.meta, v2.meta),
    'electores', coalesce(d.electores, v2.electores)
  ) into v
  from usuarios_territoriales u
  left join municipios m  on m.id = u.municipio_id
  left join provincias p  on p.id = coalesce(u.provincia_id, m.provincia_id)
  left join portal_metas_municipio v2 on v2.municipio_id = u.municipio_id
  left join portal_distritos d on d.municipio_id = u.municipio_id and d.jce_id = u.jce_id
  where u.id = auth.uid();

  if v is not null then
    perform portal_log('acceso', 'sesion', null, jsonb_build_object('rol', v->>'rol'));
  end if;
  return v;
end $$;

-- ----------------------------------------------------------------
-- 2. KPI: la meta y los colegios se recortan al distrito asignado
-- ----------------------------------------------------------------
create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
  v jsonb;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  with alcance as (
    select v2.municipio_id, v2.meta, v2.colegios
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (p_municipio is null or v2.municipio_id = p_municipio)
       and (
         v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and v2.municipio_id = portal_mun())
         or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
       )
  ),
  post as (
    select p.* from postulantes_2028 p
      join alcance a on a.municipio_id = p.municipio_id
     where (v_dist is null or p.jce_id = v_dist)
  ),
  tot as (
    select
      case when v_dist is null then (select coalesce(sum(meta),0) from alcance)
           else (select coalesce(sum(d.meta),0) from portal_distritos d where d.jce_id = v_dist) end as meta,
      case when v_dist is null then (select coalesce(sum(colegios),0) from alcance)
           else (select coalesce(sum(d.colegios),0) from portal_distritos d where d.jce_id = v_dist) end as col
  ),
  cub as (
    select count(*) n from (
      select id_colegio_padron from post
       where estado not in ('rechazado','no_aprobado') and id_colegio_padron is not null
       group by id_colegio_padron having count(*) >= 3
    ) x
  )
  select jsonb_build_object(
    'meta',               (select meta from tot),
    'colegios',           (select col  from tot),
    'colegios_cubiertos', (select n from cub),
    'total',              (select count(*) from post where estado not in ('rechazado','no_aprobado')),
    'hoy',                (select count(*) from post where created_at::date = current_date),
    'semana',             (select count(*) from post where created_at >= now() - interval '7 days'),
    'con_experiencia',    (select count(*) from post where experiencia_2024 or experiencia_2020),
    'exp_2020',           (select count(*) from post where experiencia_2020),
    'exp_2024',           (select count(*) from post where experiencia_2024),
    'firmes',             (select count(*) from post where candidato_firme),
    'por_estado',         (select jsonb_object_agg(estado, n) from (select estado, count(*) n from post group by estado) e),
    'por_cargo',          (select jsonb_object_agg(cargo_postulado, n) from (select cargo_postulado, count(*) n from post group by cargo_postulado) c)
  ) into v;
  return v;
end $$;

revoke all on function delegados.portal_kpi(integer) from public, anon;
grant execute on function delegados.portal_kpi(integer) to authenticated;

-- ----------------------------------------------------------------
-- 3. COBERTURA RESUMEN: también respeta el distrito
-- ----------------------------------------------------------------
create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
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
     where (v_dist is null or u.jce_id = v_dist)
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

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  Con la sesión de un usuario asignado a un distrito:
--   select (delegados.portal_kpi())->>'meta' as meta, (delegados.portal_kpi())->>'colegios' as colegios;
--   Pedro Corto debe devolver meta 39 y colegios 13 (no 807 / 269).
