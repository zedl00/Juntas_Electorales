-- fase80_reset_renueva_plazo.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Defecto confirmado el 27 sep con el usuario 01200549093: «↺ PIN nuevo»
-- cambiaba la clave y devolvía al usuario a «primer acceso», pero no tocaba
-- la fila de usuarios_pin_inicial. Si el PIN original ya había vencido
-- (72 h), el acceso rechazaba también el PIN nuevo con «Tu PIN inicial venció».
--
-- Ahora las dos funciones de restablecer (portal y asistente) escriben el PIN
-- nuevo en usuarios_pin_inicial. El disparador upi_caduca (fase 74) hace el
-- resto: plazo nuevo, entregado = false, y la fila vuelve a aparecer en la
-- bandeja «Accesos por enviar». Si la persona no tuviera fila (usuarios muy
-- antiguos), se crea con sus datos actuales.

create or replace function delegados._pin_inicial_renovar(p_uid uuid, p_pin text)
returns void language plpgsql security definer set search_path = delegados, public as $$
declare v_h integer; u record;
begin
  select coalesce(pin_caduca_horas, 72) into v_h from config_seguridad where id;
  select u1.cedula, u1.nombre, u1.telefono, u1.rol,
         coalesce(m.nombre, p.nombre, u1.region, 'Nacional') as territorio
    into u
    from usuarios_territoriales u1
    left join municipios m on m.id = u1.municipio_id
    left join provincias p on p.id = u1.provincia_id
   where u1.id = p_uid;
  if u.cedula is null then return; end if;

  update usuarios_pin_inicial
     set pin = p_pin, generado_en = now(), caduca_en = now() + make_interval(hours => coalesce(v_h, 72)),
         entregado = false, enviado_por = null, enviado_en = null
   where cedula = u.cedula;
  if not found then
    insert into usuarios_pin_inicial (cedula, nombre, telefono, rol, territorio, pin, entregado)
    values (u.cedula, coalesce(u.nombre, ''), coalesce(u.telefono, ''), coalesce(u.rol, ''), u.territorio, p_pin, false);
  end if;
end $$;
revoke all on function delegados._pin_inicial_renovar(uuid, text) from public, anon, authenticated;

-- ── Restablecer desde Gestión ──
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
  perform delegados._pin_inicial_renovar(v_uid, p_pin);
  update solicitudes_pin
     set estado = 'atendida', atendida_por = auth.uid(), atendida_at = now()
   where cedula = v_ced and estado = 'pendiente';
  perform portal_log('reset_pin', 'usuario', v_ced, jsonb_build_object('metodo','portal'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function delegados.portal_reset_pin(text, text) from public, anon;
grant execute on function delegados.portal_reset_pin(text, text) to authenticated;

-- ── Restablecer desde el asistente (solo rol de servicio) ──
create or replace function delegados.portal_bot_reset_pin(p_cedula text, p_pin text)
returns jsonb language plpgsql volatile security definer
set search_path = delegados, public, extensions as $$
declare
  v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
  v_uid uuid; v_rol text; v_nombre text;
begin
  if length(coalesce(p_pin,'')) < 6 then raise exception 'PIN inválido'; end if;
  select id, rol, nombre into v_uid, v_rol, v_nombre from usuarios_territoriales where cedula = v_ced;
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'No existe usuario con esa cédula.'); end if;
  if v_rol = 'admin_sne' then return jsonb_build_object('ok', false, 'error', 'Las cuentas de administración se gestionan en el sistema SNE.'); end if;
  update auth.users set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')) where id = v_uid;
  if not found then return jsonb_build_object('ok', false, 'error', 'Cuenta de acceso no localizada.'); end if;
  update usuarios_territoriales set primer_acceso = true where id = v_uid;
  perform delegados._pin_inicial_renovar(v_uid, p_pin);
  insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
  values (null, 'reset_pin', 'usuario', v_ced, jsonb_build_object('metodo','bot'));
  return jsonb_build_object('ok', true, 'nombre', v_nombre);
end $$;
revoke all on function delegados.portal_bot_reset_pin(text, text) from public, anon, authenticated;
grant execute on function delegados.portal_bot_reset_pin(text, text) to service_role;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con portal = true y bot = true.
select bool_or(p.proname = 'portal_reset_pin'     and pg_get_functiondef(p.oid) like '%_pin_inicial_renovar%') as portal,
       bool_or(p.proname = 'portal_bot_reset_pin' and pg_get_functiondef(p.oid) like '%_pin_inicial_renovar%') as bot
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.prokind = 'f' and p.proname in ('portal_reset_pin', 'portal_bot_reset_pin');
