-- fase89_gancho_sesion_y_version_minima.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Problema (7 oct 2026): una app instalada con una versión vieja (7.5) entró sin pasar por la
-- sesión única ni por el cierre por inactividad, porque esos controles viven en el código del
-- portal y la base seguía renovando su sesión. Dos remedios:
--   1) El gancho «Customize Access Token», que Supabase llama al crear y al RENOVAR cada sesión,
--      aplica los controles desde la base: niega la renovación si hay otra sesión vigente, si la
--      Comisión la cerró, o si la última señal de la app es más vieja que el límite de inactividad.
--      Solo para sesiones del portal (creadas por la función «acceso», sin contraseña directa);
--      las sesiones por contraseña de la administración en otras aplicaciones no se tocan.
--   2) «Versión mínima de la app» (config_seguridad.version_minima): el portal la lee al abrirse
--      y al volver a primer plano; si su versión es menor, descarta la copia guardada y se recarga.
-- Nota: la renovación ocurre cuando vence el token (Supabase: Authentication → Settings →
-- «JWT expiry», 3600 s por defecto). Bajarlo a 900 s hace que estos controles lleguen antes a
-- cualquier app vieja.

alter table delegados.config_seguridad add column if not exists version_minima text not null default '8.13.0';
update delegados.config_seguridad set version_minima = '8.13.0' where id and version_minima < '8.13.0';

-- ── 1. Configuración pública (sin sesión): límite de inactividad y versión mínima ──
create or replace function public.portal_config_publica()
returns json language sql stable security definer set search_path = delegados, public as $$
  select json_build_object(
    'captcha_activo',   c.captcha_activo and c.captcha_site_key is not null,
    'captcha_site_key', case when c.captcha_activo then c.captcha_site_key end,
    'inactividad_minutos', coalesce(c.inactividad_minutos, 0),
    'version_minima', coalesce(c.version_minima, '0'))
  from delegados.config_seguridad c where c.id limit 1;
$$;
revoke execute on function public.portal_config_publica() from public;
grant  execute on function public.portal_config_publica() to anon, authenticated;

-- ── 2. Gancho de tokens: los controles de sesión también desde la base ──
create or replace function public.portal_hook_token(event jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare
  v_uid uuid := (event->>'user_id')::uuid;
  v_met text := coalesce(event->>'authentication_method', '');
  v_sid text := coalesce(event->'claims'->>'session_id', '');
  v_portal boolean;
  u record; c record;
begin
  select id, rol, activo, bloqueo_definitivo, bloqueado_hasta, sesion_id, sesion_vista_en, sesion_cerrada_en, sesion_desde
    into u from delegados.usuarios_territoriales where id = v_uid;
  if u.id is null then return event; end if;   -- cuentas de otras aplicaciones

  if not u.activo or u.bloqueo_definitivo or (u.bloqueado_hasta is not null and u.bloqueado_hasta > now()) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Acceso bloqueado o desactivado. Comunícate con la Comisión.'));
  end if;
  -- Contraseña directa: solo las cuentas de administración (compartidas con otras aplicaciones)
  if v_met = 'password' and u.rol not in ('admin_sne', 'consulta_nacional') then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Entra por la pantalla de acceso del portal.'));
  end if;

  -- Fase 89: sesión del portal = creada por la función «acceso» (sin contraseña en su historial)
  begin
    v_portal := v_met <> 'password' and not exists (
      select 1 from jsonb_array_elements(coalesce(event->'claims'->'amr', '[]'::jsonb)) a where a->>'method' = 'password');
    if v_portal then
      select sesion_unica, sesion_minutos, inactividad_minutos into c from delegados.config_seguridad where id;
      -- a) La Comisión cerró la sesión y nadie ha vuelto a entrar
      if u.sesion_cerrada_en is not null and u.sesion_id is null then
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Tu sesión fue cerrada por la Comisión. Entra de nuevo con tu PIN.'));
      end if;
      -- b) Sesión única: otra sesión es la vigente
      if coalesce(c.sesion_unica, true) and u.sesion_id is not null and v_sid <> '' and u.sesion_id <> v_sid then
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Esta sesión ya no es válida: hay otra sesión abierta con tu usuario. Entra de nuevo con tu PIN.'));
      end if;
      -- c) Inactividad: la app lleva más del límite sin dar señal (o nunca la dio)
      if coalesce(c.inactividad_minutos, 0) > 0 and (u.sesion_vista_en is null
         or u.sesion_vista_en < now() - make_interval(mins => c.inactividad_minutos)) then
        update delegados.usuarios_territoriales set sesion_id = null, sesion_vista_en = null where id = u.id and (sesion_id is null or sesion_id = v_sid);
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Tu sesión se cerró por inactividad. Entra de nuevo con tu PIN.'));
      end if;
    end if;
  exception when others then
    -- Un fallo aquí nunca debe dejar a todo el mundo fuera: se deja pasar y queda en la bitácora
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'gancho_error', 'sesion', null, jsonb_build_object('msg', sqlerrm));
  end;
  return event;
end $$;
revoke execute on function public.portal_hook_token(jsonb) from public, anon, authenticated;
grant  execute on function public.portal_hook_token(jsonb) to supabase_auth_admin;

-- ── 3. Configuración: versión mínima ──
create or replace function delegados.portal_config_seguridad_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  if p ? 'sesion_minutos' and ((p->>'sesion_minutos')::integer < 1 or (p->>'sesion_minutos')::integer > 120) then
    raise exception 'Los minutos de inactividad para «conectado» deben estar entre 1 y 120';
  end if;
  if p ? 'inactividad_minutos' and ((p->>'inactividad_minutos')::integer < 0 or (p->>'inactividad_minutos')::integer > 1440) then
    raise exception 'El cierre por inactividad debe estar entre 0 (desactivado) y 1440 minutos';
  end if;
  if p ? 'version_minima' and (p->>'version_minima') !~ '^\d+\.\d+\.\d+$' then
    raise exception 'La versión mínima debe tener la forma 8.13.0';
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
    inactividad_minutos = coalesce((p->>'inactividad_minutos')::integer, inactividad_minutos),
    version_minima   = coalesce(nullif(p->>'version_minima',''), version_minima),
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con version_minima = 8.13.0, publica = 8.13.0 y gancho = true.
select (select version_minima from delegados.config_seguridad where id) as version_minima,
       public.portal_config_publica()->>'version_minima' as publica,
       (select pg_get_functiondef(p.oid) like '%session_id%' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'portal_hook_token') as gancho;
