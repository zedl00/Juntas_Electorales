-- fase86_sesion_unica.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Sesión única por usuario. Si alguien ya está conectado con un usuario, otra persona
-- no puede entrar con ese mismo usuario: ve el aviso y el intento queda en la bitácora
-- con su dirección IP y su dispositivo. La administración ve quién está conectado y
-- puede cerrar cualquier sesión.
--
-- Cómo se sabe que alguien está conectado: mientras la app está abierta envía un
-- «latido» cada 2 minutos (portal_latido). Si el último latido tiene menos de
-- «sesion_minutos» (5), el usuario cuenta como conectado. Cerrar sesión libera al
-- instante; cerrar el navegador sin salir, a los 5 minutos.
--
-- Activar o desactivar: Gestión → Configuración → Seguridad del acceso →
-- casilla «Una sola sesión por usuario» (config_seguridad.sesion_unica).

-- ── 1. Parámetros y columnas ──
alter table delegados.config_seguridad add column if not exists sesion_unica   boolean not null default true;
alter table delegados.config_seguridad add column if not exists sesion_minutos integer not null default 5;

alter table delegados.usuarios_territoriales add column if not exists sesion_id         text;
alter table delegados.usuarios_territoriales add column if not exists sesion_desde      timestamptz;
alter table delegados.usuarios_territoriales add column if not exists sesion_vista_en   timestamptz;
alter table delegados.usuarios_territoriales add column if not exists sesion_ip         text;
alter table delegados.usuarios_territoriales add column if not exists sesion_agente     text;
alter table delegados.usuarios_territoriales add column if not exists sesion_cerrada_en timestamptz;
alter table delegados.usuarios_territoriales add column if not exists ultima_ip         text;

-- ── 2. Verificación del acceso (función de servidor «acceso»), ahora con IP y dispositivo ──
-- Se elimina la firma anterior de dos parámetros para que PostgREST no tenga dos candidatas.
drop function if exists public.portal_acceso_verificar(text, text);

create or replace function public.portal_acceso_verificar(p_email text, p_pin text, p_ip text default null, p_agente text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public, extensions as $$
declare
  au record; u record; c record; v_restan integer; v_min integer; v_ok boolean;
begin
  select id, encrypted_password, email_confirmed_at into au
    from auth.users where lower(email) = lower(p_email) limit 1;
  if au.id is null then
    return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
  end if;
  select * into u from delegados.usuarios_territoriales where id = au.id;
  select * into c from delegados.config_seguridad where id;

  if u.id is not null then
    if not u.activo then
      return jsonb_build_object('ok', false, 'msg', 'Tu acceso está desactivado. Contacta a la Comisión.');
    end if;
    if u.bloqueo_definitivo then
      return jsonb_build_object('ok', false, 'msg', 'Tu acceso está bloqueado. Comunícate con la Comisión para habilitarlo.');
    end if;
    if u.bloqueado_hasta is not null and u.bloqueado_hasta > now() then
      v_min := greatest(1, ceil(extract(epoch from (u.bloqueado_hasta - now())) / 60))::integer;
      return jsonb_build_object('ok', false,
        'msg', 'Acceso bloqueado temporalmente por intentos fallidos. Vuelve a intentarlo en ' || v_min || ' minuto(s).');
    end if;
  end if;

  v_ok := au.encrypted_password is not null
          and au.encrypted_password = extensions.crypt(coalesce(p_pin, ''), au.encrypted_password);

  if v_ok then
    if u.id is not null then
      if u.primer_acceso and exists (select 1 from delegados.usuarios_pin_inicial p
                                      where p.cedula = u.cedula and p.caduca_en is not null and p.caduca_en < now()) then
        insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
        values (u.id, 'pin_vencido', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre));
        return jsonb_build_object('ok', false,
          'msg', 'Tu PIN inicial venció. Pide uno nuevo con «¿Olvidaste tu PIN?» o a la Comisión.');
      end if;

      -- Fase 86: sesión única. Solo se evalúa con el PIN correcto, para no revelar nada a quien no lo tenga.
      if coalesce(c.sesion_unica, true) and u.sesion_vista_en is not null
         and u.sesion_vista_en > now() - make_interval(mins => greatest(coalesce(c.sesion_minutos, 5), 1)) then
        insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
        values (u.id, 'sesion_duplicada', 'usuario', u.cedula, jsonb_build_object(
          'nombre', u.nombre, 'ip', p_ip, 'agente', left(p_agente, 300),
          'sesion_desde', u.sesion_desde, 'sesion_vista_en', u.sesion_vista_en,
          'sesion_ip', u.sesion_ip, 'sesion_agente', u.sesion_agente));
        return jsonb_build_object('ok', false,
          'msg', 'No puedes acceder: ya hay otra persona conectada con este usuario desde las '
                 || to_char(coalesce(u.sesion_desde, u.sesion_vista_en) at time zone 'America/Santo_Domingo', 'HH24:MI')
                 || '. Si eres tú, cierra la sesión en el otro dispositivo o espera unos minutos.');
      end if;

      update delegados.usuarios_territoriales
         set intentos_fallidos = 0,
             sesion_id = null, sesion_desde = now(), sesion_vista_en = now(),
             sesion_ip = p_ip, sesion_agente = left(p_agente, 300), sesion_cerrada_en = null,
             ultima_ip = coalesce(p_ip, ultima_ip)
       where id = u.id;
      insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (u.id, 'ingreso', 'sesion', null, jsonb_build_object('nombre', u.nombre, 'ip', p_ip, 'agente', left(p_agente, 300)));
    end if;
    return jsonb_build_object('ok', true, 'user_id', au.id, 'email', p_email);
  end if;

  -- PIN incorrecto
  if u.id is null or not coalesce(c.bloqueo_activo, true) then
    return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
  end if;

  update delegados.usuarios_territoriales set intentos_fallidos = intentos_fallidos + 1 where id = u.id
    returning intentos_fallidos into v_restan;

  if v_restan >= coalesce(c.intentos_bloqueo, 5) then
    if u.bloqueos >= 1 then
      update delegados.usuarios_territoriales
         set bloqueo_definitivo = true, bloqueo_motivo = 'Intentos fallidos repetidos', intentos_fallidos = 0
       where id = u.id;
      insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (u.id, 'bloqueo_definitivo', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'motivo', 'intentos fallidos'));
      return jsonb_build_object('ok', false,
        'msg', 'Acceso bloqueado por intentos fallidos repetidos. Solo la Comisión puede habilitarlo.');
    end if;
    update delegados.usuarios_territoriales
       set bloqueado_hasta = now() + make_interval(mins => coalesce(c.bloqueo_minutos, 15)),
           bloqueos = bloqueos + 1, intentos_fallidos = 0
     where id = u.id;
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'bloqueo_temporal', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'minutos', coalesce(c.bloqueo_minutos, 15)));
    return jsonb_build_object('ok', false,
      'msg', 'Demasiados intentos fallidos. Acceso bloqueado por ' || coalesce(c.bloqueo_minutos, 15) || ' minutos.');
  end if;

  if v_restan >= coalesce(c.intentos_aviso, 3) then
    return jsonb_build_object('ok', false,
      'msg', 'PIN incorrecto. Te quedan ' || (coalesce(c.intentos_bloqueo, 5) - v_restan) || ' intento(s) antes del bloqueo.');
  end if;
  return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
end $$;
revoke execute on function public.portal_acceso_verificar(text, text, text, text) from public, anon, authenticated;
grant  execute on function public.portal_acceso_verificar(text, text, text, text) to service_role;

-- ── 3. La función «acceso» registra el identificador de la sesión recién creada (solo rol de servicio) ──
create or replace function delegados.portal_sesion_registrar(p_user uuid, p_sesion text)
returns void language plpgsql security definer set search_path = delegados, public as $$
begin
  if auth.uid() is not null then raise exception 'Acceso no autorizado'; end if;
  update usuarios_territoriales set sesion_id = nullif(p_sesion, '') where id = p_user;
end $$;
revoke all on function delegados.portal_sesion_registrar(uuid, text) from public, anon, authenticated;
grant execute on function delegados.portal_sesion_registrar(uuid, text) to service_role;

-- ── 4. Latido: la app lo llama cada 2 minutos y al volver a primer plano ──
-- Devuelve {estado:'ok'} o {estado:'cerrada', msg} cuando esta sesión debe despedirse.
create or replace function delegados.portal_latido()
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record; c record; v_sid text := coalesce(auth.jwt()->>'session_id', '');
begin
  if auth.uid() is null then raise exception 'Acceso no autorizado'; end if;
  select id, sesion_id, sesion_desde, sesion_vista_en, sesion_cerrada_en into u from usuarios_territoriales where id = auth.uid();
  if u.id is null then return jsonb_build_object('estado', 'ok'); end if;
  select * into c from config_seguridad where id;

  if u.sesion_id is not null and u.sesion_id = v_sid then
    update usuarios_territoriales set sesion_vista_en = now() where id = u.id;
    return jsonb_build_object('estado', 'ok');
  end if;

  -- Cerrada por la administración después de que esta sesión empezó
  if u.sesion_cerrada_en is not null and (u.sesion_desde is null or u.sesion_cerrada_en >= u.sesion_desde) then
    return jsonb_build_object('estado', 'cerrada', 'msg', 'Tu sesión fue cerrada por la Comisión.');
  end if;
  -- Otra sesión distinta sigue activa y el control está encendido
  if coalesce(c.sesion_unica, true) and u.sesion_id is not null and u.sesion_vista_en is not null
     and u.sesion_vista_en > now() - make_interval(mins => greatest(coalesce(c.sesion_minutos, 5), 1)) then
    return jsonb_build_object('estado', 'cerrada', 'msg', 'Otra persona entró con tu usuario desde otro dispositivo. Si no fuiste tú, avisa a la Comisión.');
  end if;
  -- Sin sesión registrada, vencida o control apagado: esta sesión pasa a ser la vigente
  update usuarios_territoriales
     set sesion_id = nullif(v_sid, ''), sesion_vista_en = now(), sesion_desde = coalesce(sesion_desde, now()), sesion_cerrada_en = null
   where id = u.id;
  return jsonb_build_object('estado', 'ok');
end $$;
revoke all on function delegados.portal_latido() from public, anon;
grant execute on function delegados.portal_latido() to authenticated;

-- ── 5. Salir: libera la sesión al instante ──
create or replace function delegados.portal_salir()
returns void language plpgsql security definer set search_path = delegados, public as $$
declare v_sid text := coalesce(auth.jwt()->>'session_id', '');
begin
  if auth.uid() is null then return; end if;
  update usuarios_territoriales set sesion_id = null, sesion_vista_en = null
   where id = auth.uid() and (sesion_id is null or sesion_id = v_sid);
end $$;
revoke all on function delegados.portal_salir() from public, anon;
grant execute on function delegados.portal_salir() to authenticated;

-- ── 6. La administración cierra la sesión de un usuario ──
create or replace function delegados.portal_sesion_cerrar(p_user uuid)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record;
begin
  if coalesce(delegados.portal_rol(), '') <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select id, nombre, cedula, sesion_ip, sesion_desde into u from usuarios_territoriales where id = p_user;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  update usuarios_territoriales set sesion_id = null, sesion_vista_en = null, sesion_cerrada_en = now() where id = p_user;
  perform portal_log('sesion_cerrada', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'sesion_ip', u.sesion_ip, 'sesion_desde', u.sesion_desde));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function delegados.portal_sesion_cerrar(uuid) from public, anon;
grant execute on function delegados.portal_sesion_cerrar(uuid) to authenticated;

-- ── 7. Configuración: los dos parámetros nuevos ──
create or replace function delegados.portal_config_seguridad_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  if p ? 'sesion_minutos' and ((p->>'sesion_minutos')::integer < 1 or (p->>'sesion_minutos')::integer > 120) then
    raise exception 'Los minutos de inactividad deben estar entre 1 y 120';
  end if;
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
    reverificar_al_reset = coalesce((p->>'reverificar_al_reset')::boolean, reverificar_al_reset),
    sesion_unica     = coalesce((p->>'sesion_unica')::boolean, sesion_unica),
    sesion_minutos   = coalesce((p->>'sesion_minutos')::integer, sesion_minutos),
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con parametros = 2, funciones = 4, acceso_4 = true y acceso_2 = false.
select (select count(*) from information_schema.columns where table_schema = 'delegados' and table_name = 'config_seguridad' and column_name in ('sesion_unica','sesion_minutos')) as parametros,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'delegados' and p.proname in ('portal_latido','portal_salir','portal_sesion_cerrar','portal_sesion_registrar')) as funciones,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'portal_acceso_verificar' and p.pronargs = 4) as acceso_4,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'portal_acceso_verificar' and p.pronargs = 2) as acceso_2;
