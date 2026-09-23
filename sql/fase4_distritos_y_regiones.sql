-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 4 · REGIONES COMO EL SISTEMA SNE
--  Y NIVEL DE DISTRITOS DESDE LA FUENTE JCE
-- ----------------------------------------------------------------
--  · Ejecutar DESPUÉS de fase1 y fase2 (incluye y supera a fase3:
--    da igual si fase3 se ejecutó o no). Idempotente.
--  · Regiones: misma fuente que el sistema SNE que ya funciona →
--    provincias.macroregion (Norte/Este/Sur/Gran Santo Domingo),
--    y 'Exterior' para las OCLEE. Respaldo: jce_region.
--  · Distritos: las demarcaciones JCE (jce_municipio) agrupadas
--    bajo cada municipio vía _mapeo_municipio. Los colegios de los
--    distritos ya están ahí (jce_colegio.id_municipio) — ahora se
--    pueden ver y filtrar sin aplastarlos en el municipio.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. VISTA DE METAS: región alineada al sistema que funciona
-- ----------------------------------------------------------------

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

-- ----------------------------------------------------------------
-- 2. VISTA DE DISTRITOS: las demarcaciones JCE de cada municipio
--    (cabecera + distritos municipales), con sus colegios y metas
-- ----------------------------------------------------------------

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

-- ----------------------------------------------------------------
-- 3. PERFIL y COBERTURA con la misma derivación de región
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

-- Cobertura por colegio, ahora con la columna DISTRITO y filtro opcional
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
         coalesce(nullif(trim(c.codigo_colegio),''), c.descripcion, 'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion,'—')::text,
         coalesce(rc.direccion,'')::text,
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
   group by jm.id, jm.descripcion, c.id_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by 1, 5, 4;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer) to authenticated;

-- ----------------------------------------------------------------
-- 3b. TERRITORIO COHERENTE EN EL EXPEDIENTE
--     provincia_id y macroregion se completan solos desde el municipio
--     (y se corrigen los registros ya guardados sin estos datos)
-- ----------------------------------------------------------------

create or replace function delegados.trg_p28_territorio() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  select v.provincia_id, v.macroregion
    into new.provincia_id, new.macroregion
    from portal_metas_municipio v
   where v.municipio_id = new.municipio_id;
  return new;
end $$;

drop trigger if exists p28_territorio on delegados.postulantes_2028;
create trigger p28_territorio
before insert or update of municipio_id on delegados.postulantes_2028
for each row execute function delegados.trg_p28_territorio();

update delegados.postulantes_2028 p
   set provincia_id = v.provincia_id,
       macroregion  = v.macroregion
  from delegados.portal_metas_municipio v
 where v.municipio_id = p.municipio_id
   and (p.provincia_id is distinct from v.provincia_id
     or p.macroregion  is distinct from v.macroregion);

-- ----------------------------------------------------------------
-- 4. RESTABLECER PIN DESDE EL PORTAL (solo administración SNE)
--    Deja evento en la bitácora y obliga a crear PIN personal en el
--    siguiente ingreso. Las cuentas de administrador quedan
--    protegidas: su clave se gestiona en el sistema SNE, no aquí.
-- ----------------------------------------------------------------

create or replace function delegados.portal_reset_pin(p_cedula text, p_pin text)
returns jsonb
language plpgsql volatile security definer
set search_path = delegados, public, extensions as $$
declare
  v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
  v_uid uuid; v_rol text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede restablecer PIN';
  end if;
  if length(coalesce(p_pin,'')) < 6 then
    raise exception 'El PIN debe tener al menos 6 caracteres';
  end if;

  select id, rol into v_uid, v_rol from usuarios_territoriales where cedula = v_ced;
  if v_uid is null then
    raise exception 'No existe un usuario con esa cédula';
  end if;
  if v_rol = 'admin_sne' then
    raise exception 'Las cuentas de administración gestionan su clave en el sistema SNE';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf'))
   where id = v_uid;
  if not found then
    raise exception 'La cuenta de acceso no fue localizada';
  end if;

  update usuarios_territoriales set primer_acceso = true where id = v_uid;
  perform portal_log('reset_pin', 'usuario', v_ced, jsonb_build_object('metodo','portal'));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_reset_pin(text, text) from public, anon;
grant execute on function delegados.portal_reset_pin(text, text) to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN (ejecútala y confírmame los resultados) ──
--   select macroregion, count(*), sum(meta) from delegados.portal_metas_municipio group by 1 order by 3 desc;
--   select * from delegados.portal_distritos where municipio_id = (select municipio_id from delegados.portal_metas_municipio order by meta desc limit 1);
