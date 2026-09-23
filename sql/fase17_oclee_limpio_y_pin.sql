-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 17
--  EXTERIOR SIN ATRIBUCIONES ERRÓNEAS · SOLICITUD DE PIN
-- ----------------------------------------------------------------
--  1. Se elimina la ruta que emparejaba colegios del exterior por
--     PARECIDO DE NOMBRE del recinto: capturaba recintos dominicanos
--     (San Martín 59, Puerto Rico 25, Panamá 18 colegios que no les
--     corresponden). El exterior queda enlazado SOLO por la
--     demarcación declarada en jce_oclee.id_municipio.
--  2. Solicitud de restablecimiento de PIN para quien no puede
--     entrar. La función vive en public (único esquema visible sin
--     sesión) y es de ESCRITURA CIEGA: solo registra la solicitud y
--     devuelve siempre el mismo mensaje, de modo que no revela si
--     una cédula existe. El esquema delegados sigue cerrado a anon.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase16.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. EXTERIOR: enlace limpio, sin coincidencias por nombre de recinto
-- ----------------------------------------------------------------
drop view if exists delegados._colegio_oclee cascade;
create view delegados._colegio_oclee as
select u.municipio_id, u.oclee_id, c.id_colegio::integer, c.id_recinto::integer
  from delegados._unidades_oclee u
  join public.jce_colegio c on c.id_municipio = u.jce_id
 where not exists (          -- si varias oficinas comparten demarcación, no se duplica
   select 1 from delegados._unidades_oclee u2
    where u2.jce_id = u.jce_id and u2.oclee_id < u.oclee_id
 );

alter view delegados._colegio_oclee owner to postgres;
grant select on delegados._colegio_oclee to authenticated, service_role;

-- Vistas dependientes, recreadas tras el cambio anterior
create view delegados.portal_metas_municipio as
with col as (
  select u.municipio_id, cd.id_colegio, cd.id_recinto
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  union
  select municipio_id, id_colegio, id_recinto from delegados._colegio_oclee
)
select m.id as municipio_id, m.nombre, m.provincia_id,
       coalesce(nullif(btrim(m.provincia_nombre), ''), p.nombre) as provincia_nombre,
       case when m.tipo = 'OCLEE' then 'Exterior'
            else coalesce(nullif(btrim(p.macroregion), ''), nullif(btrim(m.macroregion), ''),
                          jr.descripcion::text, 'Sin región') end as macroregion,
       m.tipo, m.estatus,
       count(distinct col.id_colegio)             as colegios,
       count(distinct col.id_recinto)             as recintos,
       coalesce(sum(distinct c2.cantidad_inscritos), 0) as electores,
       count(distinct col.id_colegio) * 3         as meta,
       false as es_dm, m.id_municipio_padre as municipio_padre_id, m.tipo as provincia_tipo
from public.municipios m
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join col on col.municipio_id = m.id
left join public.jce_colegio c2 on c2.id_colegio = col.id_colegio
group by m.id, p.macroregion, p.nombre, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

create view delegados._colegio_full as
select u.municipio_id, v.provincia_id, v.macroregion, v.tipo, v.estatus,
       u.jce_id, cd.circ_id, cd.id_recinto, cd.id_colegio,
       coalesce(c.cantidad_inscritos,0) as inscritos
  from delegados._unidades_jce u
  join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  join public.jce_colegio c on c.id_colegio = cd.id_colegio
  join delegados.portal_metas_municipio v on v.municipio_id = u.municipio_id
union all
select co.municipio_id, v.provincia_id, v.macroregion, v.tipo, v.estatus,
       null::integer, null::integer, co.id_recinto, co.id_colegio,
       coalesce(c.cantidad_inscritos,0)
  from delegados._colegio_oclee co
  join public.jce_colegio c on c.id_colegio = co.id_colegio
  join delegados.portal_metas_municipio v on v.municipio_id = co.municipio_id;

alter view delegados._colegio_full owner to postgres;
grant select on delegados._colegio_full to authenticated, service_role;

create view delegados.portal_circ_municipio as
select f.municipio_id, f.provincia_id, ci.id::integer as circ_id,
       coalesce(nullif(btrim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct f.id_colegio) as colegios, count(distinct f.id_colegio)*3 as meta
  from delegados._colegio_full f
  join public.jce_circunscripcion ci on ci.id = f.circ_id
 group by f.municipio_id, f.provincia_id, ci.id, ci.descripcion, ci.codigo_circunscripcion
union all
select u.municipio_id, null::integer, null::integer, u.circ_nombre,
       count(distinct co.id_colegio), count(distinct co.id_colegio)*3
  from delegados._unidades_oclee u
  join delegados._colegio_oclee co on co.oclee_id = u.oclee_id
 group by u.municipio_id, u.circ_nombre;

alter view delegados.portal_circ_municipio owner to postgres;
revoke all on delegados.portal_circ_municipio from anon;
grant select on delegados.portal_circ_municipio to authenticated, service_role;

create view delegados.portal_circunscripciones as
with divididos as (
  select municipio_id from delegados.portal_circ_municipio
   where circ_id is not null group by municipio_id having count(*) > 1
)
select c.municipio_id, c.circ_id, c.nombre, c.colegios, c.meta
  from delegados.portal_circ_municipio c join divididos d on d.municipio_id = c.municipio_id;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. SOLICITUDES DE RESTABLECIMIENTO DE PIN
-- ----------------------------------------------------------------
create table if not exists delegados.solicitudes_pin (
  id          bigint generated always as identity primary key,
  cedula      text not null,
  canal       text,
  estado      text not null default 'pendiente' check (estado in ('pendiente','atendida','descartada')),
  created_at  timestamptz not null default now(),
  atendida_por uuid,
  atendida_at timestamptz
);
create index if not exists sp_estado_idx on delegados.solicitudes_pin (estado, created_at desc);
alter table delegados.solicitudes_pin enable row level security;
grant select, update on delegados.solicitudes_pin to authenticated;
grant all on delegados.solicitudes_pin to service_role;

drop policy if exists sp_admin on delegados.solicitudes_pin;
create policy sp_admin on delegados.solicitudes_pin
for all to authenticated using (delegados.portal_rol() = 'admin_sne')
with check (delegados.portal_rol() = 'admin_sne');

-- Función pública de escritura ciega: no consulta ni revela nada.
create or replace function public.portal_delegados_solicitar_pin(p_cedula text)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
begin
  if length(v_ced) between 8 and 15 then
    -- una sola solicitud pendiente por cédula
    if not exists (select 1 from delegados.solicitudes_pin
                    where cedula = v_ced and estado = 'pendiente') then
      insert into delegados.solicitudes_pin (cedula, canal) values (v_ced, 'portal');
    end if;
  end if;
  -- respuesta idéntica siempre: no permite averiguar si la cédula existe
  return jsonb_build_object('ok', true,
    'mensaje', 'Si la cédula corresponde a un acceso registrado, la Comisión de Juntas Electorales y OCLEE se comunicará contigo para entregarte un PIN nuevo.');
end $$;

revoke all on function public.portal_delegados_solicitar_pin(text) from public;
grant execute on function public.portal_delegados_solicitar_pin(text) to anon, authenticated;

-- Listado para la administración (con el nombre del usuario si existe)
create or replace function delegados.portal_solicitudes_pin()
returns table (id bigint, cedula text, nombre text, telefono text, rol text,
               estado text, created_at timestamptz)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede ver las solicitudes';
  end if;
  return query
  select s.id, s.cedula, coalesce(u.nombre, '— no registrada —')::text,
         u.telefono, u.rol, s.estado, s.created_at
    from solicitudes_pin s
    left join usuarios_territoriales u on u.cedula = s.cedula
   where s.estado = 'pendiente'
   order by s.created_at desc
   limit 100;
end $$;

revoke all on function delegados.portal_solicitudes_pin() from public, anon;
grant execute on function delegados.portal_solicitudes_pin() to authenticated;

-- Al restablecer un PIN se cierran las solicitudes pendientes de esa cédula
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
  if v_uid is null then raise exception 'No existe un usuario con esa cédula'; end if;
  if v_rol = 'admin_sne' then
    raise exception 'Las cuentas de administración gestionan su clave en el sistema SNE';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf'))
   where id = v_uid;
  if not found then raise exception 'La cuenta de acceso no fue localizada'; end if;

  update usuarios_territoriales set primer_acceso = true where id = v_uid;
  update solicitudes_pin
     set estado = 'atendida', atendida_por = auth.uid(), atendida_at = now()
   where cedula = v_ced and estado = 'pendiente';
  perform portal_log('reset_pin', 'usuario', v_ced, jsonb_build_object('metodo','portal'));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_reset_pin(text, text) from public, anon;
grant execute on function delegados.portal_reset_pin(text, text) to authenticated;

notify pgrst, 'reload schema';

-- ----------------------------------------------------------------
-- 3. PENDIENTES DE EMPAREJAR — consultas para completarlos a mano
-- ----------------------------------------------------------------
-- (a) Filadelfia ↔ PHILADELPHIA (el único emparejamiento evidente):
--     insert into delegados.mapeo_manual (municipio_id, jce_id, nota)
--     values (911, 19, 'OCLEE Filadelfia = PHILADELPHIA');
--
-- (b) Atlanta (925) y Connecticut (913) no tienen equivalente en la
--     JCE. Lo que sobra allá es PROVIDENCE (23) y SUIZA (9). Decidir
--     con la Secretaría si corresponden o si son oficinas nuevas.
--
-- (c) Los cuatro distritos elevados a municipio: buscar su código JCE
--     por nombre parcial y luego registrarlos en mapeo_manual.
--     select id, descripcion, id_municipio_padre, dm
--       from public.jce_municipio
--      where delegados._norm(descripcion) like '%CALETA%'
--         or delegados._norm(descripcion) like '%VICTORIA%'
--         or delegados._norm(descripcion) like '%TIREO%'
--         or delegados._norm(descripcion) like '%VILLA CENTRAL%'
--      order by descripcion;
