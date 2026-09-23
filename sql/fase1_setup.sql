-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 1 · CONFIGURACIÓN DE BASE DE DATOS
--  Secretaría Nacional Electoral · Fuerza del Pueblo
-- ----------------------------------------------------------------
--  · Ejecutar COMPLETO en el SQL Editor de Supabase (una sola vez).
--  · TODO el portal vive en su propio esquema: «delegados».
--    Nada se crea en public; el sistema SNE no se toca.
--  · PASO OBLIGATORIO DESPUÉS DE EJECUTAR ESTE SCRIPT:
--    Supabase → Settings → API → "Exposed schemas" → agregar
--    «delegados» a la lista y guardar. Sin esto, la aplicación
--    no puede consultar el esquema (error PGRST106).
--  · Al final hay un paso manual (crear tu perfil de administrador).
--  · Para revertir el portal por completo:  drop schema delegados cascade;
-- ================================================================

create schema if not exists delegados;

grant usage on schema delegados to authenticated, service_role;
-- anon no recibe privilegios: todo el portal exige sesión iniciada.

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. TABLAS DEL PORTAL (esquema delegados)
-- ----------------------------------------------------------------

create table if not exists delegados.usuarios_territoriales (
  id                uuid primary key references auth.users(id) on delete cascade,
  cedula            varchar(20) not null unique,
  nombre            text not null,
  telefono          text,
  rol               text not null check (rol in
                      ('presidente','secretario_general','enc_electoral',
                       'coordinador_regional','supervisor_provincial','admin_sne')),
  municipio_id      integer references public.municipios(id),
  provincia_id      integer references public.provincias(id),
  region            text,
  activo            boolean not null default true,
  primer_acceso     boolean not null default true,
  acuse_instructivo timestamptz,
  ultimo_acceso     timestamptz,
  created_by        uuid,
  created_at        timestamptz not null default now()
);

create index if not exists ut_municipio_idx on delegados.usuarios_territoriales (municipio_id);
create index if not exists ut_provincia_idx on delegados.usuarios_territoriales (provincia_id);

create table if not exists delegados.postulantes_2028 (
  id                 bigint generated always as identity primary key,
  numero_formulario  text unique,
  cedula             varchar(20) not null unique,
  nombres            text not null,
  apellido1          text not null,
  apellido2          text,
  sexo               character(1),
  fecha_nacimiento   date,
  telefono           text,
  whatsapp           text,
  email              text,
  direccion          text,
  nivel_academico    text,
  ocupacion          text,
  municipio_id       integer not null references public.municipios(id),
  provincia_id       integer,
  macroregion        text,
  id_colegio_padron  integer,
  codigo_colegio     text,
  colegio_desc       text,
  codigo_recinto     text,
  recinto_nombre     text,
  circunscripcion    text,
  lugar_votacion     character(1),
  cargo_postulado    text not null check (cargo_postulado in
                       ('delegado_titular','suplente_delegado','observador_escrutinio','indistinto')),
  experiencia_2024   boolean not null default false,
  experiencia_detalle text,
  requisitos         jsonb not null default '{}'::jsonb,
  estado             text not null default 'postulado' check (estado in
                       ('postulado','validado','devuelto','rechazado',
                        'en_formacion','aprobado','no_aprobado','designado','acreditado')),
  notas              text,
  registrado_por     uuid references delegados.usuarios_territoriales(id),
  validado_por       uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists p28_municipio_idx  on delegados.postulantes_2028 (municipio_id);
create index if not exists p28_provincia_idx  on delegados.postulantes_2028 (provincia_id);
create index if not exists p28_estado_idx     on delegados.postulantes_2028 (estado);
create index if not exists p28_cargo_idx      on delegados.postulantes_2028 (cargo_postulado);
create index if not exists p28_colegio_idx    on delegados.postulantes_2028 (id_colegio_padron);
create index if not exists p28_created_idx    on delegados.postulantes_2028 (created_at desc);

create table if not exists delegados.postulantes_bitacora (
  id            bigint generated always as identity primary key,
  postulante_id bigint references delegados.postulantes_2028(id) on delete cascade,
  usuario_id    uuid,
  accion        text not null,
  detalle       jsonb,
  created_at    timestamptz not null default now()
);

create index if not exists pb_postulante_idx on delegados.postulantes_bitacora (postulante_id);

-- ----------------------------------------------------------------
-- 2. FUNCIONES AUXILIARES DE PERFIL (evitan recursión en RLS)
-- ----------------------------------------------------------------

create or replace function delegados.portal_rol() returns text
language sql stable security definer set search_path = delegados, public as
$$ select rol from usuarios_territoriales where id = auth.uid() and activo $$;

create or replace function delegados.portal_mun() returns integer
language sql stable security definer set search_path = delegados, public as
$$ select municipio_id from usuarios_territoriales where id = auth.uid() and activo $$;

create or replace function delegados.portal_prov() returns integer
language sql stable security definer set search_path = delegados, public as
$$ select provincia_id from usuarios_territoriales where id = auth.uid() and activo $$;

create or replace function delegados.portal_region() returns text
language sql stable security definer set search_path = delegados, public as
$$ select region from usuarios_territoriales where id = auth.uid() and activo $$;

revoke all on function delegados.portal_rol()    from public, anon;
revoke all on function delegados.portal_mun()    from public, anon;
revoke all on function delegados.portal_prov()   from public, anon;
revoke all on function delegados.portal_region() from public, anon;
grant execute on function delegados.portal_rol()    to authenticated;
grant execute on function delegados.portal_mun()    to authenticated;
grant execute on function delegados.portal_prov()   to authenticated;
grant execute on function delegados.portal_region() to authenticated;

-- ----------------------------------------------------------------
-- 3. SEGURIDAD: privilegios del esquema + RLS
-- ----------------------------------------------------------------
-- En un esquema propio no aplican los privilegios por defecto de
-- public, así que se otorgan explícitos (las políticas RLS siguen
-- decidiendo QUÉ filas ve o toca cada rol).

grant select, insert, update, delete on delegados.usuarios_territoriales to authenticated;
grant select, insert, update, delete on delegados.postulantes_2028       to authenticated;
grant select                          on delegados.postulantes_bitacora   to authenticated;
grant usage, select on all sequences in schema delegados to authenticated;

grant all on all tables    in schema delegados to service_role;
grant all on all sequences in schema delegados to service_role;

-- Objetos que se creen en el futuro dentro del esquema (Fase 3)
alter default privileges in schema delegados grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema delegados grant usage, select on sequences to authenticated;
alter default privileges in schema delegados grant execute on functions to authenticated;
alter default privileges in schema delegados grant all on tables to service_role;
alter default privileges in schema delegados grant all on sequences to service_role;

alter table delegados.usuarios_territoriales enable row level security;
alter table delegados.postulantes_2028       enable row level security;
alter table delegados.postulantes_bitacora   enable row level security;

-- --- usuarios_territoriales ---
drop policy if exists ut_select on delegados.usuarios_territoriales;
create policy ut_select on delegados.usuarios_territoriales
for select to authenticated using (
  id = auth.uid()
  or delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun())
  or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
  or (delegados.portal_rol() = 'coordinador_regional'  and region = delegados.portal_region())
);

drop policy if exists ut_insert on delegados.usuarios_territoriales;
create policy ut_insert on delegados.usuarios_territoriales
for insert to authenticated with check (delegados.portal_rol() = 'admin_sne');

drop policy if exists ut_update on delegados.usuarios_territoriales;
create policy ut_update on delegados.usuarios_territoriales
for update to authenticated
using (delegados.portal_rol() = 'admin_sne')
with check (delegados.portal_rol() = 'admin_sne');

drop policy if exists ut_delete on delegados.usuarios_territoriales;
create policy ut_delete on delegados.usuarios_territoriales
for delete to authenticated using (delegados.portal_rol() = 'admin_sne');

-- --- postulantes_2028 ---
drop policy if exists p28_select on delegados.postulantes_2028;
create policy p28_select on delegados.postulantes_2028
for select to authenticated using (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun())
  or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
  or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
);

drop policy if exists p28_insert on delegados.postulantes_2028;
create policy p28_insert on delegados.postulantes_2028
for insert to authenticated with check (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun())
);

drop policy if exists p28_update on delegados.postulantes_2028;
create policy p28_update on delegados.postulantes_2028
for update to authenticated
using (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun()
      and estado in ('postulado','devuelto'))
)
with check (
  delegados.portal_rol() = 'admin_sne'
  or (delegados.portal_rol() = 'enc_electoral' and municipio_id = delegados.portal_mun()
      and estado in ('postulado','devuelto'))
);

drop policy if exists p28_delete on delegados.postulantes_2028;
create policy p28_delete on delegados.postulantes_2028
for delete to authenticated using (delegados.portal_rol() = 'admin_sne');

-- --- postulantes_bitacora (solo lectura según alcance; escribe un trigger) ---
drop policy if exists pb_select on delegados.postulantes_bitacora;
create policy pb_select on delegados.postulantes_bitacora
for select to authenticated using (
  delegados.portal_rol() = 'admin_sne'
  or exists (select 1 from delegados.postulantes_2028 p where p.id = postulante_id)
);

-- ----------------------------------------------------------------
-- 4. TRIGGERS: folio automático, updated_at y auditoría
-- ----------------------------------------------------------------

create or replace function delegados.trg_p28_before_insert() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
declare v_seq integer;
begin
  -- folio correlativo por municipio, a prueba de concurrencia
  perform pg_advisory_xact_lock(hashtext('p28_folio'), new.municipio_id);
  select coalesce(max(nullif(split_part(numero_formulario,'-',2),'')::integer), 0) + 1
    into v_seq
    from postulantes_2028
   where municipio_id = new.municipio_id;
  new.numero_formulario := lpad(new.municipio_id::text, 4, '0') || '-' || lpad(v_seq::text, 5, '0');

  -- completar datos territoriales desde municipios
  select m.provincia_id, m.macroregion
    into new.provincia_id, new.macroregion
    from municipios m where m.id = new.municipio_id;

  if new.registrado_por is null then new.registrado_por := auth.uid(); end if;
  new.cedula := regexp_replace(new.cedula, '\D', '', 'g');
  return new;
end $$;

drop trigger if exists p28_before_insert on delegados.postulantes_2028;
create trigger p28_before_insert
before insert on delegados.postulantes_2028
for each row execute function delegados.trg_p28_before_insert();

create or replace function delegados.trg_p28_touch() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists p28_touch on delegados.postulantes_2028;
create trigger p28_touch
before update on delegados.postulantes_2028
for each row execute function delegados.trg_p28_touch();

create or replace function delegados.trg_p28_audit() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  if tg_op = 'INSERT' then
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (new.id, auth.uid(), 'registro',
            jsonb_build_object('numero', new.numero_formulario, 'cargo', new.cargo_postulado,
                               'municipio_id', new.municipio_id));
  elsif tg_op = 'UPDATE' then
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (new.id, auth.uid(),
            case when old.estado is distinct from new.estado then 'cambio_estado' else 'edicion' end,
            jsonb_build_object('estado_anterior', old.estado, 'estado_nuevo', new.estado));
  elsif tg_op = 'DELETE' then
    insert into postulantes_bitacora (postulante_id, usuario_id, accion, detalle)
    values (old.id, auth.uid(), 'eliminacion',
            jsonb_build_object('numero', old.numero_formulario, 'cedula', old.cedula));
    return old;
  end if;
  return new;
end $$;

drop trigger if exists p28_audit on delegados.postulantes_2028;
create trigger p28_audit
after insert or update or delete on delegados.postulantes_2028
for each row execute function delegados.trg_p28_audit();

-- ----------------------------------------------------------------
-- 5. VISTA DE METAS POR TERRITORIO (3 × colegios de cada municipio)
-- ----------------------------------------------------------------

create or replace view delegados.portal_metas_municipio as
select m.id            as municipio_id,
       m.nombre,
       m.provincia_id,
       m.provincia_nombre,
       m.macroregion,
       m.tipo,
       m.estatus,
       count(distinct c.id_colegio)              as colegios,
       count(distinct c.id_recinto)              as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct c.id_colegio) * 3          as meta
from public.municipios m
left join public._mapeo_municipio mm on mm.id_actual = m.id
left join public.jce_colegio c       on c.id_municipio = mm.id_jce
group by m.id;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 6. RPC: perfil del usuario conectado (y registra último acceso)
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

  return v;
end $$;

revoke all on function delegados.portal_mi_perfil() from public, anon;
grant execute on function delegados.portal_mi_perfil() to authenticated;

-- ----------------------------------------------------------------
-- 7. RPC: búsqueda de cédula en el padrón (lectura controlada,
--         nunca se expone la tabla jce_padron al portal)
-- ----------------------------------------------------------------

create or replace function delegados.portal_buscar_cedula(p_ced text) returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
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

  if not found then
    return jsonb_build_object('encontrado', false);
  end if;

  select mm.id_actual into v_mun_app
    from _mapeo_municipio mm where mm.id_jce = r.id_municipio limit 1;
  if v_mun_app is not null then
    select nombre into v_mun_app_nombre from municipios where id = v_mun_app;
  end if;

  -- Cruce con historial 2024 (blindado: si la tabla o columna difiere,
  -- la búsqueda de padrón sigue funcionando y la experiencia queda en 0)
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

revoke all on function delegados.portal_buscar_cedula(text) from public, anon;
grant execute on function delegados.portal_buscar_cedula(text) to authenticated;

-- ----------------------------------------------------------------
-- 8. RPC: KPI del panel (respeta el alcance del rol)
-- ----------------------------------------------------------------

create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_mun integer;
  v_prov integer;
  v_reg text;
  v jsonb;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;

  if v_rol in ('presidente','secretario_general','enc_electoral') then
    v_mun := portal_mun();
  elsif v_rol = 'supervisor_provincial' then
    v_prov := portal_prov(); v_mun := p_municipio;
  elsif v_rol = 'coordinador_regional' then
    v_reg := portal_region(); v_mun := p_municipio;
  else
    v_mun := p_municipio;  -- admin_sne
  end if;

  with alcance as (
    select v2.municipio_id, v2.colegios, v2.meta
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (v_mun  is null or v2.municipio_id = v_mun)
       and (v_prov is null or v2.provincia_id = v_prov)
       and (v_reg  is null or v2.macroregion = v_reg)
  ),
  pos as (
    select p.* from postulantes_2028 p
     where p.municipio_id in (select municipio_id from alcance)
  )
  select jsonb_build_object(
    'meta',      coalesce((select sum(meta) from alcance), 0),
    'colegios',  coalesce((select sum(colegios) from alcance), 0),
    'total',     (select count(*) from pos),
    'hoy',       (select count(*) from pos where created_at::date = current_date),
    'semana',    (select count(*) from pos where created_at >= now() - interval '7 days'),
    'con_experiencia', (select count(*) from pos where experiencia_2024),
    'colegios_cubiertos', (select count(distinct id_colegio_padron) from pos where id_colegio_padron is not null),
    'por_estado', coalesce((select jsonb_object_agg(estado, n)
                     from (select estado, count(*) n from pos group by estado) e), '{}'::jsonb),
    'por_cargo',  coalesce((select jsonb_object_agg(cargo_postulado, n)
                     from (select cargo_postulado, count(*) n from pos group by cargo_postulado) c2), '{}'::jsonb),
    'por_sexo',   coalesce((select jsonb_object_agg(coalesce(sexo,'?'), n)
                     from (select sexo, count(*) n from pos group by sexo) s2), '{}'::jsonb)
  ) into v;

  return v;
end $$;

revoke all on function delegados.portal_kpi(integer) from public, anon;
grant execute on function delegados.portal_kpi(integer) to authenticated;

-- ----------------------------------------------------------------
-- 9. RPC: tabla de avance por territorio (para ranking y semáforo)
-- ----------------------------------------------------------------

create or replace function delegados.portal_kpi_territorios()
returns table (
  municipio_id integer, municipio text, provincia_id integer, provincia text,
  macroregion text, tipo text, colegios bigint, meta bigint,
  postulados bigint, validados bigint, en_formacion bigint,
  designados bigint, otros bigint, total bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;

  return query
  select v2.municipio_id, v2.nombre::text, v2.provincia_id, v2.provincia_nombre::text,
         v2.macroregion::text, v2.tipo::text, v2.colegios, v2.meta,
         count(*) filter (where p.estado = 'postulado'),
         count(*) filter (where p.estado = 'validado'),
         count(*) filter (where p.estado in ('en_formacion','aprobado')),
         count(*) filter (where p.estado in ('designado','acreditado')),
         count(*) filter (where p.estado in ('devuelto','rechazado','no_aprobado')),
         count(p.id)
    from portal_metas_municipio v2
    left join postulantes_2028 p on p.municipio_id = v2.municipio_id
   where (v2.estatus is null or v2.estatus <> 'I')
     and (
       v_rol = 'admin_sne'
       or (v_rol in ('presidente','secretario_general','enc_electoral')
           and v2.municipio_id = portal_mun())
       or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
       or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
     )
   group by v2.municipio_id, v2.nombre, v2.provincia_id, v2.provincia_nombre,
            v2.macroregion, v2.tipo, v2.colegios, v2.meta
   order by count(p.id) desc, v2.meta desc;
end $$;

revoke all on function delegados.portal_kpi_territorios() from public, anon;
grant execute on function delegados.portal_kpi_territorios() to authenticated;

-- ----------------------------------------------------------------
-- 10. RPC: acciones del propio usuario (PIN cambiado / acuse leído)
-- ----------------------------------------------------------------

create or replace function delegados.portal_pin_cambiado() returns void
language sql volatile security definer set search_path = delegados, public as
$$ update usuarios_territoriales set primer_acceso = false where id = auth.uid() $$;

create or replace function delegados.portal_acuse_instructivo() returns timestamptz
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v timestamptz;
begin
  update usuarios_territoriales
     set acuse_instructivo = coalesce(acuse_instructivo, now())
   where id = auth.uid()
   returning acuse_instructivo into v;
  return v;
end $$;

revoke all on function delegados.portal_pin_cambiado() from public, anon;
revoke all on function delegados.portal_acuse_instructivo() from public, anon;
grant execute on function delegados.portal_pin_cambiado() to authenticated;
grant execute on function delegados.portal_acuse_instructivo() to authenticated;

-- ================================================================
-- 11. PASO MANUAL · CREAR TU PERFIL DE ADMINISTRADOR
-- ----------------------------------------------------------------
-- Edita tu email del SNE y tu cédula real, y ejecuta SOLO este bloque.
-- (El SQL Editor corre como postgres, por eso puede insertar.)
-- ================================================================
/*
insert into delegados.usuarios_territoriales (id, cedula, nombre, rol, created_by)
select u.id, '00100000000', u.nombre_completo, 'admin_sne', u.id
  from public.usuarios_sistema u
 where u.email = 'TU_EMAIL_DEL_SNE_AQUI'
on conflict (id) do update
   set rol = 'admin_sne', activo = true;
*/

-- ================================================================
-- FIN · Verificación rápida (opcional):
--   select * from delegados.portal_metas_municipio order by meta desc limit 10;
--   select delegados.portal_kpi();
-- RECUERDA: Settings → API → Exposed schemas → agregar «delegados».
-- ================================================================
