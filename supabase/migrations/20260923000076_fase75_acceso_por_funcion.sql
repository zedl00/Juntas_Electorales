-- fase75_acceso_por_funcion.sql · Portal de Delegados 2028
-- Idempotente.
--
-- El gancho «Password Verification Attempt» no existe en el plan Pro. El acceso
-- pasa a hacerse por una función de servidor (Edge Function «acceso»):
--   1. public.portal_acceso_verificar(email, pin): comprueba bloqueo, verifica el
--      PIN contra auth.users y cuenta los fallos con las reglas configuradas.
--      Solo la puede llamar el rol de servicio (la función de servidor).
--   2. public.portal_hook_token(event): gancho «Customize Access Token» (sí
--      disponible en Pro). Niega la sesión a cualquier usuario del portal que
--      esté bloqueado o que intente entrar por contraseña directa, saltándose la
--      función de servidor. Se aplica también al refrescar sesiones.
-- La función del gancho de verificación (fase 74) se conserva por si el plan
-- cambia, pero no se usa.

-- ── 1. Verificación del PIN y conteo de intentos (solo service_role) ──
create or replace function public.portal_acceso_verificar(p_email text, p_pin text)
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
      update delegados.usuarios_territoriales set intentos_fallidos = 0 where id = u.id;
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
revoke execute on function public.portal_acceso_verificar(text, text) from public, anon, authenticated;
grant  execute on function public.portal_acceso_verificar(text, text) to service_role;

-- ── 2. Gancho «Customize Access Token»: sin función de servidor no hay sesión; bloqueado no hay sesión ──
create or replace function public.portal_hook_token(event jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare
  v_uid uuid := (event->>'user_id')::uuid;
  v_met text := coalesce(event->>'authentication_method', '');
  u record;
begin
  select id, activo, bloqueo_definitivo, bloqueado_hasta
    into u from delegados.usuarios_territoriales where id = v_uid;
  if u.id is null then return event; end if;   -- cuentas de otras aplicaciones del proyecto

  if not u.activo or u.bloqueo_definitivo or (u.bloqueado_hasta is not null and u.bloqueado_hasta > now()) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Acceso bloqueado o desactivado. Comunícate con la Comisión.'));
  end if;
  if v_met = 'password' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Entra por la pantalla de acceso del portal.'));
  end if;
  return event;
end $$;
revoke execute on function public.portal_hook_token(jsonb) from public, anon, authenticated;
grant  execute on function public.portal_hook_token(jsonb) to supabase_auth_admin;
grant  usage on schema public to supabase_auth_admin;

-- Comprobación (sin sesión). Esperado: 2 filas.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('portal_acceso_verificar','portal_hook_token') order by 1;
