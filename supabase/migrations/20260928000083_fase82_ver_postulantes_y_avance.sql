-- fase82_ver_postulantes_y_avance.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Decisión del 28 sep: nadie ve listados de personas salvo la administración
-- o quien tenga el parámetro «Ver postulantes» en su usuario (en falso para
-- todos, de cualquier rol). Cada quien lee siempre lo que él mismo registró:
-- lo exige el registro, que devuelve la fila creada para mostrar el número de
-- formulario e imprimir. La pantalla Avance (solo cifras) queda para todos.
--
-- 1. Parámetro ver_postulantes en el usuario y función portal_ve_postulantes().
-- 2. Lectura de expedientes y formularios: admin todo; lo propio siempre;
--    el alcance territorial solo con el parámetro.
-- 3. El perfil informa el parámetro.
-- 4. Las funciones de avance por territorio (municipios, distritos, colegios)
--    usan portal_ve_municipio, que entiende «provincia sin municipio».
-- 5. La lista de personas sin colegio (Asignación) exige el parámetro.

-- ── 1. Parámetro ──
alter table delegados.usuarios_territoriales
  add column if not exists ver_postulantes boolean not null default false;
comment on column delegados.usuarios_territoriales.ver_postulantes is
  'Puede ver listados de personas de su alcance. La administración siempre puede.';

create or replace function delegados.portal_ve_postulantes()
returns boolean language sql stable security definer set search_path = delegados, public as $$
  select delegados.portal_rol() is not null
     and coalesce((select u.rol = 'admin_sne' or coalesce(u.ver_postulantes, false)
                     from delegados.usuarios_territoriales u
                    where u.id = auth.uid()), false)
$$;
revoke all on function delegados.portal_ve_postulantes() from public, anon;
grant execute on function delegados.portal_ve_postulantes() to authenticated;

-- ── 2. Lectura ──
drop policy if exists p28_select on delegados.postulantes_2028;
create policy p28_select on delegados.postulantes_2028
for select to authenticated using (
  delegados.portal_rol() = 'admin_sne'
  or registrado_por = auth.uid()
  or (delegados.portal_ve_postulantes() and (
        delegados.portal_rol() = 'consulta_nacional'
     or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun()
         and (delegados.portal_distrito() is null or jce_id = delegados.portal_distrito()))
     or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
     or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
     or (delegados.portal_mun() is null and delegados.portal_prov() is not null
         and delegados.portal_rol() in ('presidente','secretario_general','enc_electoral')
         and provincia_id = delegados.portal_prov())
  ))
);

drop policy if exists ff_select on delegados.formularios_firmados;
create policy ff_select on delegados.formularios_firmados
for select to authenticated using (
  delegados.portal_rol() = 'admin_sne'
  or exists (
    select 1 from delegados.postulantes_2028 p
     where p.id = formularios_firmados.postulante_id
       and (p.registrado_por = auth.uid()
            or (delegados.portal_ve_postulantes() and (
                  delegados.portal_rol() = 'consulta_nacional'
               or p.municipio_id = delegados.portal_mun()
               or (delegados.portal_rol() = 'supervisor_provincial' and p.provincia_id = delegados.portal_prov())
               or (delegados.portal_rol() = 'coordinador_regional'  and p.macroregion = delegados.portal_region())
               or (delegados.portal_mun() is null and delegados.portal_prov() is not null
                   and delegados.portal_rol() in ('presidente','secretario_general','enc_electoral')
                   and p.provincia_id = delegados.portal_prov()))))
  )
);

-- ── 3. Perfil ──
create or replace function delegados.portal_mi_perfil(p_agente text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v jsonb; c record;
begin
  update usuarios_territoriales set ultimo_acceso = now() where id = auth.uid();
  update usuarios_territoriales
     set primer_ingreso_en = now(), primer_ingreso_agente = left(p_agente, 300)
   where id = auth.uid() and primer_ingreso_en is null;
  select * into c from config_seguridad where id;

  select jsonb_build_object(
    'id', u.id, 'cedula', u.cedula, 'nombre', u.nombre, 'telefono', u.telefono,
    'rol', u.rol, 'activo', u.activo, 'primer_acceso', u.primer_acceso,
    'acuse_instructivo', u.acuse_instructivo,
    'ver_distritos', u.ver_distritos,
    'ver_postulantes', (u.rol = 'admin_sne' or coalesce(u.ver_postulantes, false)),
    'puede_registrar', delegados.portal_puede_registrar(),
    'puede_imprimir', coalesce(u.puede_imprimir,
        u.rol in ('presidente','secretario_general','enc_electoral',
                  'admin_sne','consulta_nacional','supervisor_provincial','coordinador_regional')),
    'municipio_id', u.municipio_id, 'municipio', m.nombre,
    'jce_id', u.jce_id, 'distrito', d.nombre,
    'junta', m.junta_nombre, 'tipo_territorio', m.tipo,
    'provincia_id', coalesce(u.provincia_id, m.provincia_id),
    'provincia', coalesce(p.nombre, m.provincia_nombre),
    'region', coalesce(u.region, v2.macroregion),
    'colegios', coalesce(d.colegios, v2.colegios),
    'meta', coalesce(d.meta, v2.meta),
    'electores', coalesce(d.electores, v2.electores),
    'verificar_identidad', coalesce(c.verificar_padron, true) and u.verificado_padron_en is null and u.rol <> 'admin_sne',
    'identidad_campos', coalesce(c.identidad_campos, 'fecha'),
    'confirmacion_pendiente', coalesce(c.confirmar_sne, true) and u.confirmado_sne_en is null and u.rol <> 'admin_sne',
    'bloqueo_definitivo', u.bloqueo_definitivo
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

-- ── 4. Avance por territorio con el alcance real del usuario ──
create or replace function delegados.portal_kpi_territorios()
returns table(municipio_id integer, municipio text, provincia_id integer, provincia text, macroregion text, tipo text,
              colegios bigint, meta bigint, postulados bigint, validados bigint, en_formacion bigint,
              designados bigint, otros bigint, total bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
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
     and delegados.portal_ve_municipio(v2.municipio_id, v2.provincia_id, v2.macroregion)
   group by v2.municipio_id, v2.nombre, v2.provincia_id, v2.provincia_nombre,
            v2.macroregion, v2.tipo, v2.colegios, v2.meta
   order by count(p.id) desc, v2.meta desc;
end $$;

create or replace function delegados.portal_kpi_distritos(p_municipio integer)
returns table(jce_id integer, distrito text, es_dm boolean, colegios bigint, meta bigint,
              total bigint, completos bigint, parciales bigint, vacios bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  select v2.provincia_id, v2.macroregion into v_prov, v_reg
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not delegados.portal_ve_municipio(p_municipio, v_prov, v_reg) then
    raise exception 'Territorio fuera de tu alcance';
  end if;

  return query
  with cole as (
    select u.jce_id as jce, u.nombre, u.es_dm, cd.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as n
      from delegados._unidades_jce u
      left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
      left join postulantes_2028 p on p.colegio_asignado = cd.id_colegio
     where u.municipio_id = p_municipio
       and (v_dist is null or u.jce_id = v_dist)
     group by u.jce_id, u.nombre, u.es_dm, cd.id_colegio
  )
  select cole.jce, cole.nombre, cole.es_dm,
         count(cole.id_colegio)::bigint,
         (count(cole.id_colegio) * 3)::bigint,
         coalesce(sum(cole.n), 0)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n >= 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n > 0 and cole.n < 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n = 0)::bigint
    from cole
   group by cole.jce, cole.nombre, cole.es_dm
   order by cole.es_dm, cole.nombre;
end $$;

create or replace function delegados.portal_cobertura_colegios(p_municipio integer, p_jce integer default null, p_circ integer default null)
returns table(distrito text, jce_id integer, circunscripcion text, circ_id integer, id_colegio integer, colegio text,
              recinto text, recinto_dir text, inscritos bigint, titulares bigint, suplentes bigint,
              observadores bigint, indistintos bigint, personas bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text; v_tipo text;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  select v2.provincia_id, v2.macroregion, v2.tipo into v_prov, v_reg, v_tipo
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not delegados.portal_ve_municipio(p_municipio, v_prov, v_reg) then
    raise exception 'Territorio fuera de tu alcance';
  end if;
  if v_dist is not null then p_jce := v_dist::integer; end if;

  if coalesce(v_tipo,'') = 'OCLEE' then
    return query
    select u.nombre::text, u.jce_id::integer, u.circ_nombre::text, null::integer,
           c.id_colegio::integer,
           coalesce(nullif(btrim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
           coalesce(rc.descripcion::text,'—')::text,
           coalesce(rc.direccion::text,'')::text,
           coalesce(max(c.cantidad_inscritos),0)::bigint,
           count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
      from delegados._unidades_oclee u
      join delegados._colegio_oclee co on co.oclee_id = u.oclee_id and co.municipio_id = u.municipio_id
      join public.jce_colegio c on c.id_colegio = co.id_colegio
      left join public.jce_recinto rc on rc.id = c.id_recinto
      left join postulantes_2028 p on p.colegio_asignado = c.id_colegio
     where u.municipio_id = p_municipio
     group by u.nombre, u.jce_id, u.circ_nombre,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by 7, 6;
  else
    return query
    select u.nombre::text, u.jce_id::integer,
           coalesce(nullif(btrim(ci.descripcion),''), 'Circ. ' || ci.codigo_circunscripcion, '—')::text,
           ci.id::integer,
           c.id_colegio::integer,
           coalesce(nullif(btrim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
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
      left join postulantes_2028 p on p.colegio_asignado = c.id_colegio
     where u.municipio_id = p_municipio
       and (p_jce  is null or u.jce_id = p_jce)
       and (p_circ is null or cd.circ_id = p_circ)
     group by u.nombre, u.jce_id, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by u.es_dm, u.nombre, coalesce(rc.descripcion,''), 6;
  end if;
end $$;

-- ── 5. Personas sin colegio (Asignación): solo con el parámetro ──
create or replace function delegados.portal_sin_colegio(p_municipio integer default null)
returns table(id bigint, numero_formulario text, cedula text, nombre text, cargo text, telefono text,
              municipio_id integer, territorio text, vota_recinto text, vota_colegio text,
              vota_municipio text, created_at timestamp with time zone)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  if not delegados.portal_ve_postulantes() then raise exception 'Sin permiso para ver listados de personas'; end if;

  return query
  select p.id, p.numero_formulario::text, p.cedula::text,
         btrim(p.nombres || ' ' || coalesce(p.apellido1,'') || ' ' || coalesce(p.apellido2,''))::text,
         p.cargo_postulado::text, p.telefono::text,
         p.municipio_id::integer,
         coalesce(coalesce(d.nombre || ' · ', '') || m.nombre, m.nombre, '')::text,
         coalesce(p.recinto_padron_desc, p.recinto_nombre, '—')::text,
         coalesce(p.colegio_padron_desc,
                  nullif(btrim(coalesce(p.codigo_colegio,'')), ''), '—')::text,
         coalesce(mp.nombre, '(fuera del padrón)')::text,
         p.created_at
    from postulantes_2028 p
    left join portal_metas_municipio m  on m.municipio_id = p.municipio_id
    left join portal_metas_municipio mp on mp.municipio_id = p.municipio_padron_id
    left join portal_distritos d on d.jce_id = p.jce_id and d.municipio_id = p.municipio_id
   where p.colegio_asignado is null
     and p.estado not in ('rechazado','no_aprobado')
     and coalesce(p.traslado_estado, '') not in ('pendiente', 'rechazado')
     and (p_municipio is null or p.municipio_id = p_municipio)
     and delegados.portal_ve_municipio(p.municipio_id, m.provincia_id, m.macroregion)
   order by m.nombre, p.created_at;
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con columna = true, politicas = 2 y funciones = 3.
select exists (select 1 from information_schema.columns
                where table_schema = 'delegados' and table_name = 'usuarios_territoriales' and column_name = 'ver_postulantes') as columna,
       (select count(*) from pg_policies
         where schemaname = 'delegados' and policyname in ('p28_select','ff_select') and qual like '%portal_ve_postulantes%') as politicas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'delegados' and p.prokind = 'f'
           and p.proname in ('portal_kpi_territorios','portal_kpi_distritos','portal_cobertura_colegios')
           and pg_get_functiondef(p.oid) like '%portal_ve_municipio%') as funciones;
