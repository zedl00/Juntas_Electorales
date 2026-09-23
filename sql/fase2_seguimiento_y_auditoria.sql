-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 2 · SEGUIMIENTO POR COLEGIO
--  Y AUDITORÍA TOTAL DE ACTIVIDADES
-- ----------------------------------------------------------------
--  · Ejecutar COMPLETO en el SQL Editor, DESPUÉS de fase1_setup.sql.
--  · Es idempotente: se puede re-ejecutar sin peligro.
--  · Todo sigue dentro del esquema «delegados». No toca public.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. REGISTRO DE EVENTOS DEL SISTEMA (accesos, consultas, usuarios…)
-- ----------------------------------------------------------------

create table if not exists delegados.eventos_sistema (
  id         bigint generated always as identity primary key,
  usuario_id uuid,
  accion     text not null,
  entidad    text,
  entidad_id text,
  detalle    jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ev_created_idx on delegados.eventos_sistema (created_at desc);
create index if not exists ev_usuario_idx on delegados.eventos_sistema (usuario_id);
create index if not exists ev_accion_idx  on delegados.eventos_sistema (accion);

alter table delegados.eventos_sistema enable row level security;
-- Nadie escribe ni lee directo: escriben las funciones/triggers
-- (security definer) y se consulta solo vía RPC portal_eventos (admin).
grant select on delegados.eventos_sistema to service_role;

create or replace function delegados.portal_log(p_accion text, p_entidad text default null,
                                                p_entidad_id text default null, p_detalle jsonb default null)
returns void language sql volatile security definer set search_path = delegados, public as
$$ insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
   values (auth.uid(), p_accion, p_entidad, p_entidad_id, p_detalle) $$;

revoke all on function delegados.portal_log(text,text,text,jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------
-- 2. AUDITORÍA ENRIQUECIDA DE POSTULANTES (antes/después campo a campo)
-- ----------------------------------------------------------------

create or replace function delegados.trg_p28_audit() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
declare
  v_old jsonb; v_new jsonb; v_cambios jsonb;
begin
  if tg_op = 'INSERT' then
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (new.id, auth.uid(), 'registro',
            jsonb_build_object('numero', new.numero_formulario, 'cargo', new.cargo_postulado,
                               'municipio_id', new.municipio_id,
                               'registro_completo', to_jsonb(new)));
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new);
    select jsonb_object_agg(e.key, jsonb_build_object('antes', v_old -> e.key, 'despues', e.value))
      into v_cambios
      from jsonb_each(v_new) e
     where e.key <> 'updated_at' and (v_old -> e.key) is distinct from e.value;
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (new.id, auth.uid(),
            case when old.estado is distinct from new.estado then 'cambio_estado' else 'edicion' end,
            jsonb_build_object('estado_anterior', old.estado, 'estado_nuevo', new.estado,
                               'numero', new.numero_formulario, 'cambios', coalesce(v_cambios, '{}'::jsonb)));
  elsif tg_op = 'DELETE' then
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (old.id, auth.uid(), 'eliminacion',
            jsonb_build_object('numero', old.numero_formulario, 'cedula', old.cedula,
                               'registro_completo', to_jsonb(old)));
    return old;
  end if;
  return new;
end $$;

-- ----------------------------------------------------------------
-- 3. AUDITORÍA DE USUARIOS TERRITORIALES (altas, ediciones, bajas)
-- ----------------------------------------------------------------

create or replace function delegados.trg_ut_audit() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
declare
  v_old jsonb; v_new jsonb; v_cambios jsonb;
begin
  if tg_op = 'INSERT' then
    insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'alta_usuario', 'usuario', new.cedula,
            jsonb_build_object('nombre', new.nombre, 'rol', new.rol,
                               'municipio_id', new.municipio_id, 'provincia_id', new.provincia_id,
                               'region', new.region));
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new);
    select jsonb_object_agg(e.key, jsonb_build_object('antes', v_old -> e.key, 'despues', e.value))
      into v_cambios
      from jsonb_each(v_new) e
     where e.key not in ('ultimo_acceso') and (v_old -> e.key) is distinct from e.value;
    if v_cambios is not null then
      insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (auth.uid(),
              case when old.activo <> new.activo
                   then (case when new.activo then 'usuario_activado' else 'usuario_desactivado' end)
                   else 'edicion_usuario' end,
              'usuario', new.cedula,
              jsonb_build_object('nombre', new.nombre, 'cambios', v_cambios));
    end if;
  elsif tg_op = 'DELETE' then
    insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'baja_usuario', 'usuario', old.cedula,
            jsonb_build_object('registro_completo', to_jsonb(old)));
    return old;
  end if;
  return new;
end $$;

drop trigger if exists ut_audit on delegados.usuarios_territoriales;
create trigger ut_audit
after insert or update or delete on delegados.usuarios_territoriales
for each row execute function delegados.trg_ut_audit();

-- ----------------------------------------------------------------
-- 4. ACCESOS Y CONSULTAS DE PADRÓN QUEDAN REGISTRADOS
--    (se redefinen las dos funciones para que dejen huella)
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
    'region', coalesce(u.region, m.macroregion),
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

  select mm.id_actual into v_mun_app
    from _mapeo_municipio mm where mm.id_jce = r.id_municipio limit 1;
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

-- ----------------------------------------------------------------
-- 5. COBERTURA POR COLEGIO ELECTORAL (la unidad mínima)
--    Un colegio está CUBIERTO cuando tiene 3 personas en proceso
--    (se excluyen rechazados y no aprobados).
-- ----------------------------------------------------------------

-- 5a · Resumen por territorio: colegios completos / parciales / sin registro
create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;

  return query
  with cole as (
    select m.id as mun_id, c.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as personas
      from public.municipios m
      join public._mapeo_municipio mm on mm.id_actual = m.id
      join public.jce_colegio c       on c.id_municipio = mm.id_jce
      left join postulantes_2028 p    on p.id_colegio_padron = c.id_colegio
                                     and p.municipio_id = m.id
     where (m.estatus is null or m.estatus <> 'I')
       and (
         v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and m.id = portal_mun())
         or (v_rol = 'supervisor_provincial' and m.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and m.macroregion = portal_region())
       )
     group by m.id, c.id_colegio
  )
  select cole.mun_id,
         count(*)::bigint,
         count(*) filter (where personas >= 3),
         count(*) filter (where personas > 0 and personas < 3),
         count(*) filter (where personas = 0)
    from cole
   group by cole.mun_id;
end $$;

revoke all on function delegados.portal_cobertura_resumen() from public, anon;
grant execute on function delegados.portal_cobertura_resumen() to authenticated;

-- 5b · Detalle de un municipio: cada colegio con su recinto y composición
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
  select m.provincia_id, m.macroregion into v_prov, v_reg
    from public.municipios m where m.id = p_municipio;
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

revoke all on function delegados.portal_cobertura_colegios(integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer) to authenticated;

-- ----------------------------------------------------------------
-- 6. RPC: BITÁCORA UNIFICADA PARA EL ADMINISTRADOR
--    (eventos del sistema + historial de postulantes, con nombre)
-- ----------------------------------------------------------------

create or replace function delegados.portal_eventos(p_limit integer default 200)
returns table (
  id bigint, created_at timestamptz, usuario text, accion text,
  entidad text, entidad_id text, detalle jsonb
)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede consultar la bitácora';
  end if;

  return query
  select * from (
    select e.id, e.created_at, coalesce(u.nombre, '—') as usuario,
           e.accion, e.entidad, e.entidad_id, e.detalle
      from eventos_sistema e
      left join usuarios_territoriales u on u.id = e.usuario_id
    union all
    select b.id, b.created_at, coalesce(u2.nombre, '—'),
           b.accion, 'postulante',
           coalesce(b.detalle->>'numero', b.postulante_id::text),
           b.detalle
      from postulantes_bitacora b
      left join usuarios_territoriales u2 on u2.id = b.usuario_id
  ) t
  order by t.created_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;

revoke all on function delegados.portal_eventos(integer) from public, anon;
grant execute on function delegados.portal_eventos(integer) to authenticated;

-- ----------------------------------------------------------------
-- FIN · La API relee su esquema automáticamente:
-- ----------------------------------------------------------------
notify pgrst, 'reload schema';

-- Verificación rápida (opcional):
--   select * from delegados.portal_cobertura_resumen() limit 5;
--   select * from delegados.portal_cobertura_colegios( <ID_MUNICIPIO> ) limit 10;
--   select * from delegados.portal_eventos(20);
