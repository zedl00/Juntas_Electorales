-- fase88_cierre_por_inactividad.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Cierre automático de sesión por inactividad. Si una persona pasa más de
-- «inactividad_minutos» sin usar el portal (sin tocar, escribir ni desplazar),
-- la app cierra la sesión y vuelve a pedir el PIN. Dos capas:
--   1) la app mide la actividad y se cierra sola, aunque esté sin conexión;
--   2) la base, en cada latido, compara la última señal recibida con el límite:
--      si la app estuvo cerrada o dormida más tiempo del permitido (por ejemplo,
--      una computadora que se abre tres días después), la sesión se cierra al
--      restaurarse, antes de mostrar nada.
-- Parámetro: Gestión → Configuración → Seguridad del acceso → «Cerrar la sesión tras N minutos sin uso».
-- 0 = desactivado.

alter table delegados.config_seguridad add column if not exists inactividad_minutos integer not null default 30;

-- ── 1. La app lee el límite sin sesión (junto con el captcha) ──
create or replace function public.portal_config_publica()
returns json language sql stable security definer set search_path = delegados, public as $$
  select json_build_object(
    'captcha_activo',   c.captcha_activo and c.captcha_site_key is not null,
    'captcha_site_key', case when c.captcha_activo then c.captcha_site_key end,
    'inactividad_minutos', coalesce(c.inactividad_minutos, 0))
  from delegados.config_seguridad c where c.id limit 1;
$$;
revoke execute on function public.portal_config_publica() from public;
grant  execute on function public.portal_config_publica() to anon, authenticated;

-- ── 2. Latido con minutos de inactividad reportados por la app ──
drop function if exists delegados.portal_latido();
create or replace function delegados.portal_latido(p_inactivo_min integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record; c record; v_sid text := coalesce(auth.jwt()->>'session_id', ''); v_lim integer;
begin
  if auth.uid() is null then raise exception 'Acceso no autorizado'; end if;
  select id, cedula, nombre, sesion_id, sesion_desde, sesion_vista_en, sesion_cerrada_en into u from usuarios_territoriales where id = auth.uid();
  if u.id is null then return jsonb_build_object('estado', 'ok'); end if;
  select * into c from config_seguridad where id;
  v_lim := coalesce(c.inactividad_minutos, 0);

  -- Fase 88: inactividad. Solo sobre la sesión vigente (misma sesión que la registrada).
  if v_lim > 0 and u.sesion_id is not null and u.sesion_id = v_sid and (
       coalesce(p_inactivo_min, 0) >= v_lim
       or (u.sesion_vista_en is not null and u.sesion_vista_en < now() - make_interval(mins => v_lim))) then
    update usuarios_territoriales set sesion_id = null, sesion_vista_en = null where id = u.id;
    insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'sesion_inactiva', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'limite_min', v_lim,
            'inactivo_min', p_inactivo_min, 'ultima_senal', u.sesion_vista_en));
    return jsonb_build_object('estado', 'cerrada', 'motivo', 'inactividad',
      'msg', 'Tu sesión se cerró por inactividad: más de ' || v_lim || ' minutos sin usar el portal. Vuelve a entrar con tu PIN.');
  end if;

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
revoke all on function delegados.portal_latido(integer) from public, anon;
grant execute on function delegados.portal_latido(integer) to authenticated;

-- ── 3. Configuración ──
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
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con parametro = 30, publica = 30, latido_viejo = false y latido_nuevo = true.
select (select inactividad_minutos from delegados.config_seguridad where id) as parametro,
       (public.portal_config_publica()->>'inactividad_minutos')::integer as publica,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'delegados' and p.proname = 'portal_latido' and p.pronargs = 0) as latido_viejo,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'delegados' and p.proname = 'portal_latido' and p.pronargs = 1) as latido_nuevo;
