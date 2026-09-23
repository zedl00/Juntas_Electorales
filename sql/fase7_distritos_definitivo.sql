-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 7 · DISTRITOS A PRUEBA DE MAPEO,
--  CIRCUNSCRIPCIONES Y USUARIOS POR DISTRITO
-- ----------------------------------------------------------------
--  Converge todo el estado (incluye y supera fase6). Idempotente.
--  · Los distritos se derivan de la JERARQUÍA JCE (id_municipio_padre),
--    de modo que aparecen aunque _mapeo_municipio solo tenga cabeceras.
--  · Circunscripción visible y filtrable (jce_recinto.id_circunscripcion).
--  · usuarios_territoriales.jce_id: encargado/presidente/secretario DE UN
--    DISTRITO → solo ve, registra y cuenta lo de su distrito (RLS real).
-- ================================================================

set search_path = delegados, public;

-- ── 0 · UNIDADES JCE por municipio: mapeo ∪ hijos de lo mapeado ──
create or replace view delegados._unidades_jce as
select distinct u.municipio_id, u.jce_id
from (
  select mm.id_actual::integer as municipio_id, mm.id_jce::integer as jce_id
    from public._mapeo_municipio mm
  union
  select mm.id_actual::integer, jm.id::integer
    from public._mapeo_municipio mm
    join public.jce_municipio jm on jm.id_municipio_padre = mm.id_jce
) u;

grant select on delegados._unidades_jce to authenticated, service_role;

-- ── 1 · Metas por municipio (colegios vía unidades: incluye DM siempre) ──
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
left join delegados._unidades_jce u  on u.municipio_id = m.id
left join public.jce_colegio c       on c.id_municipio = u.jce_id
group by m.id, p.macroregion, p.nombre, p.tipo, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ── 2 · Distritos (unidades JCE del municipio) ──
drop view if exists delegados.portal_distritos;
create view delegados.portal_distritos as
select u.municipio_id,
       u.jce_id,
       initcap(lower(coalesce(jm.descripcion, 'Demarcación ' || u.jce_id)))::text as nombre,
       (jm.id_municipio_padre is not null
         or upper(trim(coalesce(jm.dm::text,''))) in ('S','SI','1','T','TRUE','Y','V','D')) as es_dm,
       count(distinct c.id_colegio)              as colegios,
       count(distinct c.id_recinto)              as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct c.id_colegio) * 3          as meta
from delegados._unidades_jce u
join public.jce_municipio jm on jm.id = u.jce_id
left join public.jce_colegio c on c.id_municipio = u.jce_id
group by u.municipio_id, u.jce_id, jm.descripcion, jm.dm, jm.id_municipio_padre;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

-- ── 3 · Usuario por distrito ──
alter table delegados.usuarios_territoriales add column if not exists jce_id integer;

create or replace function delegados.portal_jce() returns integer
language sql stable security definer set search_path = delegados as
$$ select jce_id from usuarios_territoriales where id = auth.uid() and activo $$;

-- Alcance por distrito en la seguridad de postulantes:
drop policy if exists p28_select on delegados.postulantes_2028;
create policy p28_select on delegados.postulantes_2028
for select to authenticated using (
  delegados.portal_rol() in ('admin_sne','consulta_nacional')
  or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun()
      and (delegados.portal_jce() is null
           or id_colegio_padron is null
           or exists (select 1 from public.jce_colegio c
                       where c.id_colegio = postulantes_2028.id_colegio_padron
                         and c.id_municipio = delegados.portal_jce())))
  or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
  or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
);

drop policy if exists p28_insert on delegados.postulantes_2028;
create policy p28_insert on delegados.postulantes_2028
for insert to authenticated with check (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun()
      and (delegados.portal_jce() is null
           or id_colegio_padron is null
           or exists (select 1 from public.jce_colegio c
                       where c.id_colegio = postulantes_2028.id_colegio_padron
                         and c.id_municipio = delegados.portal_jce())))
);

drop policy if exists p28_update on delegados.postulantes_2028;
create policy p28_update on delegados.postulantes_2028
for update to authenticated
using (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun()
      and estado in ('postulado','devuelto')
      and (delegados.portal_jce() is null
           or id_colegio_padron is null
           or exists (select 1 from public.jce_colegio c
                       where c.id_colegio = postulantes_2028.id_colegio_padron
                         and c.id_municipio = delegados.portal_jce())))
)
with check (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun()
      and estado in ('postulado','devuelto'))
);

-- ── 4 · Perfil con distrito (nombre y meta del distrito cuando aplica) ──
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
    'provincia', coalesce(p.nombre, v2.provincia_nombre),
    'region', coalesce(u.region, v2.macroregion),
    'jce_id', u.jce_id,
    'distrito', d.nombre,
    'colegios', coalesce(d.colegios, v2.colegios),
    'meta',     coalesce(d.meta,     v2.meta),
    'electores',coalesce(d.electores,v2.electores)
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

-- ── 5 · KPI respetando el distrito del usuario ──
create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_jce integer := portal_jce();
  v_mun integer; v_prov integer; v_reg text; v jsonb;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  if v_rol in ('presidente','secretario_general','enc_electoral') then
    v_mun := portal_mun();
  elsif v_rol = 'supervisor_provincial' then
    v_prov := portal_prov(); v_mun := p_municipio;
  elsif v_rol = 'coordinador_regional' then
    v_reg := portal_region(); v_mun := p_municipio;
  else
    v_mun := p_municipio;
  end if;

  with pob as (
    select p.* from postulantes_2028 p
    where (v_mun  is null or p.municipio_id = v_mun)
      and (v_prov is null or p.provincia_id = v_prov)
      and (v_reg  is null or p.macroregion  = v_reg)
      and (v_jce  is null or p.id_colegio_padron is null or exists (
             select 1 from public.jce_colegio c
              where c.id_colegio = p.id_colegio_padron and c.id_municipio = v_jce))
  ),
  metas as (
    select case
             when v_jce is not null then (select d.meta from portal_distritos d
                                           where d.municipio_id = v_mun and d.jce_id = v_jce)
             else (select sum(meta) from portal_metas_municipio v2
                    where (v2.estatus is null or v2.estatus <> 'I')
                      and (v_mun  is null or v2.municipio_id = v_mun)
                      and (v_prov is null or v2.provincia_id = v_prov)
                      and (v_reg  is null or v2.macroregion  = v_reg))
           end as meta,
           case
             when v_jce is not null then (select d.colegios from portal_distritos d
                                           where d.municipio_id = v_mun and d.jce_id = v_jce)
             else (select sum(colegios) from portal_metas_municipio v2
                    where (v2.estatus is null or v2.estatus <> 'I')
                      and (v_mun  is null or v2.municipio_id = v_mun)
                      and (v_prov is null or v2.provincia_id = v_prov)
                      and (v_reg  is null or v2.macroregion  = v_reg))
           end as colegios
  )
  select jsonb_build_object(
    'meta', coalesce(metas.meta, 0),
    'colegios', coalesce(metas.colegios, 0),
    'total', (select count(*) from pob where estado not in ('rechazado','no_aprobado')),
    'colegios_cubiertos', (select count(distinct id_colegio_padron) from pob
                            where id_colegio_padron is not null
                              and estado not in ('rechazado','no_aprobado')),
    'con_experiencia', (select count(*) from pob where experiencia_2024
                          and estado not in ('rechazado','no_aprobado')),
    'hoy',    (select count(*) from pob where created_at::date = current_date),
    'semana', (select count(*) from pob where created_at >= now() - interval '7 days'),
    'por_estado', (select coalesce(jsonb_object_agg(estado, n), '{}'::jsonb)
                     from (select estado, count(*) n from pob group by estado) e),
    'por_cargo',  (select coalesce(jsonb_object_agg(cargo_postulado, n), '{}'::jsonb)
                     from (select cargo_postulado, count(*) n from pob
                            where estado not in ('rechazado','no_aprobado') group by cargo_postulado) g)
  ) into v from metas;
  return v;
end $$;

revoke all on function delegados.portal_kpi(integer) from public, anon;
grant execute on function delegados.portal_kpi(integer) to authenticated;

-- ── 6 · Cobertura por colegio: circunscripción + distrito forzado por usuario ──
drop function if exists delegados.portal_cobertura_colegios(integer, integer);
create function delegados.portal_cobertura_colegios(p_municipio integer, p_jce integer default null)
returns table (
  distrito text, jce_id integer,
  id_colegio integer, colegio text, recinto text, recinto_dir text,
  circunscripcion text,
  inscritos bigint, titulares bigint, suplentes bigint, observadores bigint,
  indistintos bigint, personas bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_jce_user integer := portal_jce();
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
  if v_rol in ('presidente','secretario_general','enc_electoral') and v_jce_user is not null then
    p_jce := v_jce_user;   -- usuario distrital: siempre su distrito
  end if;

  return query
  select initcap(lower(coalesce(jm.descripcion, '—')))::text,
         u.jce_id,
         c.id_colegio::integer,
         coalesce(nullif(trim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion::text,'—')::text,
         coalesce(rc.direccion::text,'')::text,
         coalesce(rc.id_circunscripcion::text, '')::text,
         coalesce(sum(distinct c.cantidad_inscritos),0)::bigint,
         count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
    from delegados._unidades_jce u
    join public.jce_municipio jm on jm.id = u.jce_id
    join public.jce_colegio c    on c.id_municipio = u.jce_id
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where u.municipio_id = p_municipio
     and (p_jce is null or u.jce_id = p_jce)
   group by u.jce_id, jm.descripcion, c.id_colegio, c.codigo_colegio, c.descripcion,
            rc.descripcion, rc.direccion, rc.id_circunscripcion
   order by 1, 5, 4;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer) to authenticated;

-- ── 7 · Resumen de cobertura respetando distrito del usuario ──
create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_jce integer := portal_jce();
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
     where (v_jce is null or u.jce_id = v_jce)
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

-- ── 8 · Búsqueda de cédula: devuelve también la unidad JCE (para avisos de distrito) ──
--     (se conserva todo lo de fase2; solo se añade 'jce_municipio_id')
create or replace function delegados.portal_buscar_cedula(p_ced text) returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare
  v_ced text := regexp_replace(coalesce(p_ced,''), '\D', '', 'g');
  v_fmt text; r record; v_mun_app integer; v_mun_app_nombre text;
  v_exp integer := 0; v_post record; v_es_usuario boolean := false;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  if length(v_ced) < 8 then return jsonb_build_object('encontrado', false, 'error', 'Cédula incompleta'); end if;

  select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
         pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
         pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
         pa.id_municipio,
         c.descripcion  as colegio_desc, rc.descripcion as recinto_desc,
         rc.direccion   as recinto_dir,  jm.descripcion as jce_municipio
    into r
    from jce_padron pa
    left join jce_colegio  c  on c.id_colegio = pa.id_colegio
    left join jce_recinto  rc on rc.id = c.id_recinto
    left join jce_municipio jm on jm.id = pa.id_municipio
   where pa.cedula = v_ced and pa.activo limit 1;

  if not found and length(v_ced) = 11 then
    v_fmt := substr(v_ced,1,3) || '-' || substr(v_ced,4,7) || '-' || substr(v_ced,11,1);
    select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
           pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
           pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
           pa.id_municipio,
           c.descripcion  as colegio_desc, rc.descripcion as recinto_desc,
           rc.direccion   as recinto_dir,  jm.descripcion as jce_municipio
      into r
      from jce_padron pa
      left join jce_colegio  c  on c.id_colegio = pa.id_colegio
      left join jce_recinto  rc on rc.id = c.id_recinto
      left join jce_municipio jm on jm.id = pa.id_municipio
     where pa.cedula = v_fmt and pa.activo limit 1;
  end if;

  perform portal_log('consulta_padron', 'cedula', v_ced, jsonb_build_object('encontrado', found));
  if not found then return jsonb_build_object('encontrado', false); end if;

  select mm.id_actual into v_mun_app from _mapeo_municipio mm where mm.id_jce = r.id_municipio limit 1;
  if v_mun_app is null then
    select u.municipio_id into v_mun_app from delegados._unidades_jce u where u.jce_id = r.id_municipio limit 1;
  end if;
  if v_mun_app is not null then select nombre into v_mun_app_nombre from municipios where id = v_mun_app; end if;

  begin
    select count(*) into v_exp from historial_delegado h
     where regexp_replace(coalesce(h.cedula,''), '\D', '', 'g') = v_ced;
  exception when undefined_table or undefined_column then v_exp := 0; end;

  select numero_formulario, estado, municipio_id into v_post
    from postulantes_2028 where cedula = v_ced limit 1;

  select exists(select 1 from usuarios_territoriales
                 where regexp_replace(cedula, '\D', '', 'g') = v_ced) into v_es_usuario;

  return jsonb_build_object(
    'encontrado', true, 'cedula', v_ced, 'nombres', r.nombres,
    'apellido1', r.apellido1, 'apellido2', r.apellido2, 'sexo', r.id_sexo,
    'fecha_nacimiento', r.fecha_nacimiento, 'lugar_votacion', r.lugar_votacion,
    'id_colegio', r.id_colegio, 'codigo_colegio', r.codigo_colegio,
    'colegio_desc', r.colegio_desc, 'codigo_recinto', r.codigo_recinto,
    'recinto', r.recinto_desc, 'recinto_dir', r.recinto_dir,
    'circunscripcion', r.codigo_circunscripcion,
    'jce_municipio', r.jce_municipio,
    'jce_municipio_id', r.id_municipio,
    'municipio_app_id', v_mun_app, 'municipio_app', v_mun_app_nombre,
    'experiencia_2024', v_exp > 0, 'experiencia_veces', v_exp,
    'ya_postulado', v_post.numero_formulario is not null,
    'postulado_numero', v_post.numero_formulario,
    'postulado_estado', v_post.estado,
    'postulado_municipio_id', v_post.municipio_id,
    'es_usuario', v_es_usuario
  );
end $$;

-- ── 9 · Circunscripciones de un municipio (para el filtro de Postulantes) ──
create or replace function delegados.portal_circunscripciones(p_municipio integer)
returns table (circunscripcion text)
language sql stable security definer set search_path = delegados, public as $$
  select distinct rc.id_circunscripcion::text
    from delegados._unidades_jce u
    join public.jce_colegio c on c.id_municipio = u.jce_id
    join public.jce_recinto rc on rc.id = c.id_recinto
   where u.municipio_id = p_municipio and rc.id_circunscripcion is not null
   order by 1
$$;
revoke all on function delegados.portal_circunscripciones(integer) from public, anon;
grant execute on function delegados.portal_circunscripciones(integer) to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN CLAVE (córrela y compárteme los números) ──
-- select count(*) as unidades, count(distinct municipio_id) as municipios from delegados._unidades_jce;
-- select * from delegados.portal_distritos where municipio_id in (select municipio_id from delegados._unidades_jce group by 1 having count(*) > 1 limit 1);
