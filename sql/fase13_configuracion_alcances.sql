-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 13
--  CONFIGURACIÓN DE ALCANCE POR USUARIO
-- ----------------------------------------------------------------
--   · ver_distritos    : el usuario municipal ve (o no) el desglose
--                        por distrito de su municipio.
--   · puede_registrar  : habilita el registro a un rol que por
--                        defecto solo consulta (p. ej. un supervisor
--                        provincial que además opera).
--   Ambas son configuraciones, no permisos nuevos: el alcance
--   territorial sigue mandando y se aplica en la base de datos.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Idempotente.
-- ================================================================

set search_path = delegados, public;

alter table delegados.usuarios_territoriales
  add column if not exists ver_distritos boolean not null default true;

alter table delegados.usuarios_territoriales
  add column if not exists puede_registrar boolean;   -- null = según el rol

comment on column delegados.usuarios_territoriales.ver_distritos is
  'Si es falso, el usuario municipal ve su municipio como una sola unidad (sin desglose por distrito).';
comment on column delegados.usuarios_territoriales.puede_registrar is
  'null = según el rol (solo enc_electoral registra). true/false = excepción autorizada por la SNE.';

-- Helper: ¿este usuario puede registrar?
create or replace function delegados.portal_puede_registrar() returns boolean
language sql stable security definer set search_path = delegados, public as $$
  select coalesce(u.puede_registrar, u.rol in ('enc_electoral','admin_sne'))
    from usuarios_territoriales u
   where u.id = auth.uid() and u.activo
$$;

revoke all on function delegados.portal_puede_registrar() from public, anon;
grant execute on function delegados.portal_puede_registrar() to authenticated;

-- El registro respeta la configuración (y el alcance territorial de siempre)
drop policy if exists p28_insert on delegados.postulantes_2028;
create policy p28_insert on delegados.postulantes_2028
for insert to authenticated with check (
  delegados.portal_rol() = 'admin_sne'
  or (
    delegados.portal_puede_registrar()
    and (
      (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun()
        and (delegados.portal_distrito() is null or jce_id = delegados.portal_distrito()))
      or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
      or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
    )
  )
);

-- El perfil informa ambas configuraciones al portal
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

notify pgrst, 'reload schema';
