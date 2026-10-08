-- fase90_defensa_activa.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Defensa activa (8 oct 2026), a raíz de la revisión de seguridad completa:
--   A. Registro de TODOS los intentos de acceso (IP, país, cédula, resultado) en acceso_intentos.
--   B. Límite por conexión: más de N fallos desde la misma IP en M minutos → esa IP queda fuera
--      el resto de la ventana. Cierra la puerta a que alguien bloquee usuarios a propósito
--      probando PIN de cédulas ajenas, y a la fuerza bruta distribuida por cédulas.
--   C. Bloqueo escalonado: 15, 30 y 60 minutos; definitivo al tercer agotamiento (parámetro).
--      Antes era definitivo al segundo, lo que hacía trivial dejar a alguien fuera.
--   D. Modo de emergencia «solo administración»: cierra el portal a todos menos a admin_sne,
--      expulsa las sesiones abiertas (latido y gancho) y no deja entrar hasta que se levante.
--   E. Registro de exportaciones (CSV) igual que las impresiones.
--   F. Alertas de seguridad para Gestión: IPs con muchos fallos, usuarios desde varias IP,
--      sesiones duplicadas, consultas de padrón excesivas, exportaciones, accesos de madrugada,
--      accesos desde fuera del país.

-- ── 1. Parámetros ──
alter table delegados.config_seguridad add column if not exists ip_max_fallos integer not null default 20;
alter table delegados.config_seguridad add column if not exists ip_ventana_min integer not null default 15;
alter table delegados.config_seguridad add column if not exists bloqueos_para_definitivo integer not null default 3;
alter table delegados.config_seguridad add column if not exists modo_emergencia text not null default 'normal';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'cfg_modo_emergencia_chk') then
    alter table delegados.config_seguridad add constraint cfg_modo_emergencia_chk check (modo_emergencia in ('normal','solo_admin'));
  end if;
end $$;

-- ── 2. Intentos de acceso ──
create table if not exists delegados.acceso_intentos (
  id bigserial primary key,
  ip text, pais text, cedula text,
  exito boolean not null,
  motivo text,
  agente text,
  created_at timestamptz not null default now()
);
create index if not exists acceso_intentos_ip_idx on delegados.acceso_intentos (ip, created_at desc);
create index if not exists acceso_intentos_ced_idx on delegados.acceso_intentos (cedula, created_at desc);
alter table delegados.acceso_intentos enable row level security;
grant select on delegados.acceso_intentos to authenticated;
drop policy if exists ai_admin on delegados.acceso_intentos;
create policy ai_admin on delegados.acceso_intentos for select to authenticated using (delegados.portal_rol() = 'admin_sne');

create or replace function delegados._acceso_intento(p_ip text, p_pais text, p_ced text, p_exito boolean, p_motivo text, p_agente text)
returns void language sql security definer set search_path = delegados, public as $$
  insert into delegados.acceso_intentos (ip, pais, cedula, exito, motivo, agente)
  values (nullif(p_ip,''), nullif(upper(p_pais),''), left(p_ced, 20), p_exito, p_motivo, left(p_agente, 300))
$$;
revoke all on function delegados._acceso_intento(text, text, text, boolean, text, text) from public, anon, authenticated;

-- ── 3. Verificación del acceso (función de servidor «acceso»), con IP, país, límite por conexión y modo de emergencia ──
drop function if exists public.portal_acceso_verificar(text, text, text, text);
create or replace function public.portal_acceso_verificar(p_email text, p_pin text, p_ip text default null, p_agente text default null, p_pais text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public, extensions as $$
declare
  au record; u record; c record; v_restan integer; v_min integer; v_ok boolean;
  v_ced text := split_part(coalesce(p_email,''), '@', 1); v_fallos_ip integer;
begin
  select * into c from delegados.config_seguridad where id;

  -- B. Límite por conexión
  if p_ip is not null and p_ip <> '' and coalesce(c.ip_max_fallos, 0) > 0 then
    select count(*) into v_fallos_ip from delegados.acceso_intentos
     where ip = p_ip and not exito and created_at > now() - make_interval(mins => greatest(coalesce(c.ip_ventana_min, 15), 1));
    if v_fallos_ip >= c.ip_max_fallos then
      perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'ip_bloqueada', p_agente);
      if not exists (select 1 from delegados.eventos_sistema where accion = 'acceso_ip_bloqueada' and entidad_id = p_ip
                        and created_at > now() - make_interval(mins => greatest(coalesce(c.ip_ventana_min, 15), 1))) then
        insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
        values (null, 'acceso_ip_bloqueada', 'ip', p_ip, jsonb_build_object('ip', p_ip, 'pais', p_pais, 'fallos', v_fallos_ip, 'ventana_min', c.ip_ventana_min, 'agente', left(p_agente, 200)));
      end if;
      return jsonb_build_object('ok', false, 'msg', 'Demasiados intentos desde esta conexión. Espera ' || coalesce(c.ip_ventana_min, 15) || ' minutos e inténtalo de nuevo.');
    end if;
  end if;

  select id, encrypted_password, email_confirmed_at into au
    from auth.users where lower(email) = lower(p_email) limit 1;
  if au.id is null then
    perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'cuenta_inexistente', p_agente);
    return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
  end if;
  select * into u from delegados.usuarios_territoriales where id = au.id;

  if u.id is not null then
    if not u.activo then
      perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'desactivado', p_agente);
      return jsonb_build_object('ok', false, 'msg', 'Tu acceso está desactivado. Contacta a la Comisión.');
    end if;
    if u.bloqueo_definitivo then
      perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'bloqueo_definitivo', p_agente);
      return jsonb_build_object('ok', false, 'msg', 'Tu acceso está bloqueado. Comunícate con la Comisión para habilitarlo.');
    end if;
    if u.bloqueado_hasta is not null and u.bloqueado_hasta > now() then
      v_min := greatest(1, ceil(extract(epoch from (u.bloqueado_hasta - now())) / 60))::integer;
      perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'bloqueo_temporal', p_agente);
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
        perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'pin_vencido', p_agente);
        return jsonb_build_object('ok', false,
          'msg', 'Tu PIN inicial venció. Pide uno nuevo con «¿Olvidaste tu PIN?» o a la Comisión.');
      end if;

      -- D. Modo de emergencia: solo la administración entra
      if coalesce(c.modo_emergencia, 'normal') = 'solo_admin' and u.rol <> 'admin_sne' then
        perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'portal_cerrado', p_agente);
        return jsonb_build_object('ok', false, 'msg', 'El portal está cerrado temporalmente por la Comisión. Inténtalo más tarde.');
      end if;

      -- Sesión única (fase 86)
      if coalesce(c.sesion_unica, true) and u.sesion_vista_en is not null
         and u.sesion_vista_en > now() - make_interval(mins => greatest(coalesce(c.sesion_minutos, 5), 1)) then
        insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
        values (u.id, 'sesion_duplicada', 'usuario', u.cedula, jsonb_build_object(
          'nombre', u.nombre, 'ip', p_ip, 'pais', p_pais, 'agente', left(p_agente, 300),
          'sesion_desde', u.sesion_desde, 'sesion_vista_en', u.sesion_vista_en,
          'sesion_ip', u.sesion_ip, 'sesion_agente', u.sesion_agente));
        perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'sesion_duplicada', p_agente);
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
      values (u.id, 'ingreso', 'sesion', null, jsonb_build_object('nombre', u.nombre, 'ip', p_ip, 'pais', p_pais, 'agente', left(p_agente, 300)));
    end if;
    perform delegados._acceso_intento(p_ip, p_pais, v_ced, true, 'ok', p_agente);
    return jsonb_build_object('ok', true, 'user_id', au.id, 'email', p_email);
  end if;

  -- PIN incorrecto
  perform delegados._acceso_intento(p_ip, p_pais, v_ced, false, 'pin_incorrecto', p_agente);
  if u.id is null or not coalesce(c.bloqueo_activo, true) then
    return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
  end if;

  update delegados.usuarios_territoriales set intentos_fallidos = intentos_fallidos + 1 where id = u.id
    returning intentos_fallidos into v_restan;

  if v_restan >= coalesce(c.intentos_bloqueo, 5) then
    -- C. Escalonado: definitivo al agotar los intentos por N-ésima vez
    if u.bloqueos >= greatest(coalesce(c.bloqueos_para_definitivo, 3), 1) - 1 then
      update delegados.usuarios_territoriales
         set bloqueo_definitivo = true, bloqueo_motivo = 'Intentos fallidos repetidos', intentos_fallidos = 0
       where id = u.id;
      insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (u.id, 'bloqueo_definitivo', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'motivo', 'intentos fallidos', 'ip', p_ip, 'pais', p_pais));
      return jsonb_build_object('ok', false,
        'msg', 'Acceso bloqueado por intentos fallidos repetidos. Solo la Comisión puede habilitarlo.');
    end if;
    v_min := least(coalesce(c.bloqueo_minutos, 15) * power(2, u.bloqueos)::integer, 1440);
    update delegados.usuarios_territoriales
       set bloqueado_hasta = now() + make_interval(mins => v_min),
           bloqueos = bloqueos + 1, intentos_fallidos = 0
     where id = u.id;
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'bloqueo_temporal', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'minutos', v_min, 'vez', u.bloqueos + 1, 'ip', p_ip, 'pais', p_pais));
    return jsonb_build_object('ok', false,
      'msg', 'Demasiados intentos fallidos. Acceso bloqueado por ' || v_min || ' minutos.');
  end if;

  if v_restan >= coalesce(c.intentos_aviso, 3) then
    return jsonb_build_object('ok', false,
      'msg', 'PIN incorrecto. Te quedan ' || (coalesce(c.intentos_bloqueo, 5) - v_restan) || ' intento(s) antes del bloqueo.');
  end if;
  return jsonb_build_object('ok', false, 'msg', 'Cédula o PIN incorrectos.');
end $$;
revoke execute on function public.portal_acceso_verificar(text, text, text, text, text) from public, anon, authenticated;
grant  execute on function public.portal_acceso_verificar(text, text, text, text, text) to service_role;

-- ── 4. Gancho: modo de emergencia también al renovar ──
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
  if u.id is null then return event; end if;

  if not u.activo or u.bloqueo_definitivo or (u.bloqueado_hasta is not null and u.bloqueado_hasta > now()) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Acceso bloqueado o desactivado. Comunícate con la Comisión.'));
  end if;
  if v_met = 'password' and u.rol not in ('admin_sne', 'consulta_nacional') then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Entra por la pantalla de acceso del portal.'));
  end if;

  begin
    v_portal := v_met <> 'password' and not exists (
      select 1 from jsonb_array_elements(coalesce(event->'claims'->'amr', '[]'::jsonb)) a where a->>'method' = 'password');
    if v_portal then
      select sesion_unica, sesion_minutos, inactividad_minutos, modo_emergencia into c from delegados.config_seguridad where id;
      if coalesce(c.modo_emergencia, 'normal') = 'solo_admin' and u.rol <> 'admin_sne' then
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'El portal está cerrado temporalmente por la Comisión.'));
      end if;
      if u.sesion_cerrada_en is not null and u.sesion_id is null then
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Tu sesión fue cerrada por la Comisión. Entra de nuevo con tu PIN.'));
      end if;
      if coalesce(c.sesion_unica, true) and u.sesion_id is not null and v_sid <> '' and u.sesion_id <> v_sid then
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Esta sesión ya no es válida: hay otra sesión abierta con tu usuario. Entra de nuevo con tu PIN.'));
      end if;
      if coalesce(c.inactividad_minutos, 0) > 0 and (u.sesion_vista_en is null
         or u.sesion_vista_en < now() - make_interval(mins => c.inactividad_minutos)) then
        update delegados.usuarios_territoriales set sesion_id = null, sesion_vista_en = null where id = u.id and (sesion_id is null or sesion_id = v_sid);
        return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Tu sesión se cerró por inactividad. Entra de nuevo con tu PIN.'));
      end if;
    end if;
  exception when others then
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'gancho_error', 'sesion', null, jsonb_build_object('msg', sqlerrm));
  end;
  return event;
end $$;
revoke execute on function public.portal_hook_token(jsonb) from public, anon, authenticated;
grant  execute on function public.portal_hook_token(jsonb) to supabase_auth_admin;

-- ── 5. Latido: modo de emergencia expulsa en menos de 2 minutos ──
create or replace function delegados.portal_latido(p_inactivo_min integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record; c record; v_sid text := coalesce(auth.jwt()->>'session_id', ''); v_lim integer;
begin
  if auth.uid() is null then raise exception 'Acceso no autorizado'; end if;
  select id, rol, cedula, nombre, sesion_id, sesion_desde, sesion_vista_en, sesion_cerrada_en into u from usuarios_territoriales where id = auth.uid();
  if u.id is null then return jsonb_build_object('estado', 'ok'); end if;
  select * into c from config_seguridad where id;
  v_lim := coalesce(c.inactividad_minutos, 0);

  if coalesce(c.modo_emergencia, 'normal') = 'solo_admin' and u.rol <> 'admin_sne' then
    update usuarios_territoriales set sesion_id = null, sesion_vista_en = null where id = u.id;
    return jsonb_build_object('estado', 'cerrada', 'motivo', 'emergencia', 'msg', 'El portal está cerrado temporalmente por la Comisión. Inténtalo más tarde.');
  end if;

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
  if u.sesion_cerrada_en is not null and (u.sesion_desde is null or u.sesion_cerrada_en >= u.sesion_desde) then
    return jsonb_build_object('estado', 'cerrada', 'msg', 'Tu sesión fue cerrada por la Comisión.');
  end if;
  if coalesce(c.sesion_unica, true) and u.sesion_id is not null and u.sesion_vista_en is not null
     and u.sesion_vista_en > now() - make_interval(mins => greatest(coalesce(c.sesion_minutos, 5), 1)) then
    return jsonb_build_object('estado', 'cerrada', 'msg', 'Otra persona entró con tu usuario desde otro dispositivo. Si no fuiste tú, avisa a la Comisión.');
  end if;
  update usuarios_territoriales
     set sesion_id = nullif(v_sid, ''), sesion_vista_en = now(), sesion_desde = coalesce(sesion_desde, now()), sesion_cerrada_en = null
   where id = u.id;
  return jsonb_build_object('estado', 'ok');
end $$;
revoke all on function delegados.portal_latido(integer) from public, anon;
grant execute on function delegados.portal_latido(integer) to authenticated;

-- ── 6. Modo de emergencia (interruptor de la administración) ──
create or replace function delegados.portal_modo_emergencia(p_modo text)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_n integer := 0;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  if p_modo not in ('normal','solo_admin') then raise exception 'Modo no válido'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  update config_seguridad set modo_emergencia = p_modo, actualizado_por = v_nom, actualizado_en = now() where id;
  if p_modo = 'solo_admin' then
    update usuarios_territoriales set sesion_id = null, sesion_vista_en = null, sesion_cerrada_en = now()
     where rol <> 'admin_sne' and sesion_id is not null;
    get diagnostics v_n = row_count;
  end if;
  perform portal_log('modo_emergencia', 'configuracion', null, jsonb_build_object('modo', p_modo, 'sesiones_cerradas', v_n, 'por', v_nom));
  return jsonb_build_object('ok', true, 'modo', p_modo, 'sesiones_cerradas', v_n);
end $$;
revoke all on function delegados.portal_modo_emergencia(text) from public, anon;
grant execute on function delegados.portal_modo_emergencia(text) to authenticated;

-- ── 7. Registro de exportaciones ──
create or replace function delegados.portal_log_exportacion(p_tipo text, p_registros integer default null, p_detalle text default null)
returns void language plpgsql security definer set search_path = delegados, public as $$
begin
  if auth.uid() is null then raise exception 'Acceso no autorizado'; end if;
  perform portal_log('exportacion', 'documento', null, jsonb_build_object('tipo', left(p_tipo, 60), 'registros', p_registros, 'detalle', left(p_detalle, 300)));
end $$;
revoke all on function delegados.portal_log_exportacion(text, integer, text) from public, anon;
grant execute on function delegados.portal_log_exportacion(text, integer, text) to authenticated;

-- ── 8. Alertas de seguridad ──
create or replace function delegados.portal_alertas(p_horas integer default 24)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare v_desde timestamptz := now() - make_interval(hours => least(greatest(coalesce(p_horas, 24), 1), 720)); c record;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select * into c from config_seguridad where id;
  return jsonb_build_object(
    'desde', v_desde, 'horas', least(greatest(coalesce(p_horas, 24), 1), 720),
    'modo_emergencia', c.modo_emergencia,
    'intentos', (select jsonb_build_object('total', count(*), 'exitosos', count(*) filter (where exito), 'fallidos', count(*) filter (where not exito),
                        'ips', count(distinct ip), 'cedulas', count(distinct cedula)) from acceso_intentos where created_at > v_desde),
    'ips_sospechosas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select ip, max(pais) as pais, count(*) as fallos, count(distinct cedula) as cedulas, max(created_at) as ultimo,
               bool_or(motivo = 'ip_bloqueada') as bloqueada
          from acceso_intentos where not exito and created_at > v_desde and ip is not null
         group by ip having count(*) >= 5 order by count(*) desc limit 20) x),
    'usuarios_varias_ip', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.cedula, u.rol, count(distinct e.detalle->>'ip') as ips,
               string_agg(distinct coalesce(e.detalle->>'ip','?') || coalesce(' ' || (e.detalle->>'pais'), ''), ', ') as lista
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion = 'ingreso' and e.created_at > v_desde
         group by u.id, u.nombre, u.cedula, u.rol having count(distinct e.detalle->>'ip') > 1 order by 4 desc limit 20) x),
    'sesiones_duplicadas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.cedula, e.detalle->>'ip' as ip, e.detalle->>'pais' as pais, e.detalle->>'sesion_ip' as sesion_ip, e.created_at
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion = 'sesion_duplicada' and e.created_at > v_desde order by e.created_at desc limit 20) x),
    'consultas_excesivas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.cedula, u.rol, count(*) as consultas
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion in ('consulta_padron','consulta_bot') and e.created_at > v_desde
         group by u.id, u.nombre, u.cedula, u.rol having count(*) >= 40 order by 4 desc limit 20) x),
    'exportaciones', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.rol, e.accion, e.detalle->>'tipo' as tipo, (e.detalle->>'registros')::integer as registros, e.created_at
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion in ('exportacion','impresion') and e.created_at > v_desde order by e.created_at desc limit 30) x),
    'bloqueos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select e.accion, e.detalle->>'nombre' as nombre, e.entidad_id as cedula, e.detalle->>'ip' as ip, e.created_at
          from eventos_sistema e where e.accion in ('bloqueo_temporal','bloqueo_definitivo','acceso_ip_bloqueada') and e.created_at > v_desde
         order by e.created_at desc limit 20) x),
    'madrugada', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.rol, e.detalle->>'ip' as ip, e.created_at
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion = 'ingreso' and e.created_at > v_desde
           and extract(hour from e.created_at at time zone 'America/Santo_Domingo') between 0 and 5
         order by e.created_at desc limit 20) x),
    'paises', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select coalesce(pais, '?') as pais, count(*) as intentos, count(*) filter (where exito) as exitosos
          from acceso_intentos where created_at > v_desde group by 1 order by 2 desc limit 10) x),
    'fuera_pais', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select u.nombre, u.rol, e.detalle->>'ip' as ip, e.detalle->>'pais' as pais, e.created_at
          from eventos_sistema e join usuarios_territoriales u on u.id = e.usuario_id
         where e.accion = 'ingreso' and e.created_at > v_desde and coalesce(e.detalle->>'pais','DO') not in ('DO','')
         order by e.created_at desc limit 20) x)
  );
end $$;
revoke all on function delegados.portal_alertas(integer) from public, anon;
grant execute on function delegados.portal_alertas(integer) to authenticated;

-- ── 9. Configuración ──
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
  if p ? 'ip_max_fallos' and ((p->>'ip_max_fallos')::integer < 0 or (p->>'ip_max_fallos')::integer > 1000) then
    raise exception 'El límite de fallos por conexión debe estar entre 0 (desactivado) y 1000';
  end if;
  if p ? 'ip_ventana_min' and ((p->>'ip_ventana_min')::integer < 1 or (p->>'ip_ventana_min')::integer > 1440) then
    raise exception 'La ventana por conexión debe estar entre 1 y 1440 minutos';
  end if;
  if p ? 'bloqueos_para_definitivo' and ((p->>'bloqueos_para_definitivo')::integer < 1 or (p->>'bloqueos_para_definitivo')::integer > 10) then
    raise exception 'Los bloqueos antes del definitivo deben estar entre 1 y 10';
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
    ip_max_fallos    = coalesce((p->>'ip_max_fallos')::integer, ip_max_fallos),
    ip_ventana_min   = coalesce((p->>'ip_ventana_min')::integer, ip_ventana_min),
    bloqueos_para_definitivo = coalesce((p->>'bloqueos_para_definitivo')::integer, bloqueos_para_definitivo),
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con parametros = 4, tabla = true, acceso_5 = true, acceso_4 = false, funciones = 4.
select (select count(*) from information_schema.columns where table_schema = 'delegados' and table_name = 'config_seguridad'
          and column_name in ('ip_max_fallos','ip_ventana_min','bloqueos_para_definitivo','modo_emergencia')) as parametros,
       exists (select 1 from information_schema.tables where table_schema = 'delegados' and table_name = 'acceso_intentos') as tabla,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'portal_acceso_verificar' and p.pronargs = 5) as acceso_5,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'portal_acceso_verificar' and p.pronargs = 4) as acceso_4,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'delegados'
          and p.proname in ('portal_modo_emergencia','portal_log_exportacion','portal_alertas','_acceso_intento')) as funciones;
