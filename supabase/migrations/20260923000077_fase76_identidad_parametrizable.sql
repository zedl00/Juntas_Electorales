-- fase76_identidad_parametrizable.sql · Portal de Delegados 2028
-- Idempotente.
--
-- 1. Qué se pide para verificar la identidad contra el padrón es configurable:
--      'fecha'           → solo fecha de nacimiento (por defecto, lo más ágil)
--      'fecha_municipio' → fecha de nacimiento y municipio donde vota
-- 2. La administración de la SNE nunca pasa por la verificación de identidad ni
--    puede quedar en bloqueo definitivo por ella (la base lo garantiza, no solo
--    la pantalla).
-- 3. El perfil expone el parámetro para que la pantalla pida solo lo configurado.

alter table delegados.config_seguridad add column if not exists identidad_campos text not null default 'fecha';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'config_seguridad_identidad_campos_chk') then
    alter table delegados.config_seguridad
      add constraint config_seguridad_identidad_campos_chk check (identidad_campos in ('fecha','fecha_municipio'));
  end if;
end $$;

create or replace function delegados.portal_verificar_identidad(p_fecha_nac date, p_municipio_id integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record; pa record; v_mun integer; v_ok boolean; v_int integer; c record;
begin
  select * into u from usuarios_territoriales where id = auth.uid() and activo;
  if u.id is null then raise exception 'Acceso no autorizado'; end if;
  select * into c from config_seguridad where id;

  -- La administración no se verifica contra el padrón
  if u.rol = 'admin_sne' then
    update usuarios_territoriales set verificado_padron_en = coalesce(verificado_padron_en, now()) where id = u.id;
    return jsonb_build_object('ok', true, 'ya', true);
  end if;
  if u.verificado_padron_en is not null then return jsonb_build_object('ok', true, 'ya', true); end if;

  select pa2.fecha_nacimiento, pa2.id_municipio, pa2.lugar_votacion into pa
    from public.jce_padron pa2 where pa2.cedula = u.cedula and pa2.activo limit 1;
  if pa.fecha_nacimiento is null then
    update usuarios_territoriales set verificado_padron_en = now() where id = u.id;
    perform portal_log('identidad_sin_padron', 'usuario', u.cedula, null);
    return jsonb_build_object('ok', true, 'sin_padron', true);
  end if;

  v_ok := (pa.fecha_nacimiento = p_fecha_nac);
  if v_ok and coalesce(c.identidad_campos, 'fecha') = 'fecha_municipio' and pa.lugar_votacion <> 'E' then
    select x.municipio_id into v_mun from delegados._unidades_jce x where x.jce_id = pa.id_municipio limit 1;
    v_ok := (v_mun is null or v_mun = p_municipio_id);
  end if;

  if v_ok then
    update usuarios_territoriales set verificado_padron_en = now(), intentos_identidad = 0 where id = u.id;
    perform portal_log('identidad_verificada', 'usuario', u.cedula, null);
    return jsonb_build_object('ok', true);
  end if;

  update usuarios_territoriales set intentos_identidad = intentos_identidad + 1 where id = u.id
    returning intentos_identidad into v_int;
  if v_int >= 3 then
    update usuarios_territoriales
       set bloqueo_definitivo = true, bloqueo_motivo = 'No superó la verificación de identidad' where id = u.id;
    perform portal_log('bloqueo_definitivo', 'usuario', u.cedula, jsonb_build_object('motivo', 'identidad'));
    return jsonb_build_object('ok', false, 'bloqueado', true,
      'msg', 'Los datos no coinciden con el padrón. Tu acceso quedó bloqueado; comunícate con la Comisión.');
  end if;
  perform portal_log('identidad_fallida', 'usuario', u.cedula, jsonb_build_object('intento', v_int));
  return jsonb_build_object('ok', false, 'restantes', 3 - v_int,
    'msg', 'Los datos no coinciden con el padrón. Te quedan ' || (3 - v_int) || ' intento(s).');
end $$;

-- La configuración guarda también el parámetro nuevo
create or replace function delegados.portal_config_seguridad_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  update config_seguridad set
    captcha_activo   = coalesce((p->>'captcha_activo')::boolean, captcha_activo),
    captcha_site_key = case when p ? 'captcha_site_key' then nullif(trim(p->>'captcha_site_key'), '') else captcha_site_key end,
    bloqueo_activo   = coalesce((p->>'bloqueo_activo')::boolean, bloqueo_activo),
    intentos_aviso   = coalesce((p->>'intentos_aviso')::integer, intentos_aviso),
    intentos_bloqueo = coalesce((p->>'intentos_bloqueo')::integer, intentos_bloqueo),
    bloqueo_minutos  = coalesce((p->>'bloqueo_minutos')::integer, bloqueo_minutos),
    verificar_padron = coalesce((p->>'verificar_padron')::boolean, verificar_padron),
    identidad_campos = coalesce(nullif(p->>'identidad_campos',''), identidad_campos),
    pin_caduca_horas = coalesce((p->>'pin_caduca_horas')::integer, pin_caduca_horas),
    confirmar_sne    = coalesce((p->>'confirmar_sne')::boolean, confirmar_sne),
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

-- El perfil dice qué campos pedir
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

-- Comprobación (sin sesión). Esperado: 1 fila con identidad_campos = 'fecha'.
select identidad_campos from delegados.config_seguridad where id;
