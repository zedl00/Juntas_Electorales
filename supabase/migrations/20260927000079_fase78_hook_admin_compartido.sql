-- fase78_hook_admin_compartido.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Las cuentas de administración (admin_sne, consulta_nacional) se comparten con
-- otras aplicaciones del mismo proyecto (Análisis Electoral), que entran por
-- contraseña directa. El gancho de token dejaba fuera a esas cuentas en esas
-- aplicaciones. Ahora: los roles de administración pueden entrar por contraseña
-- en cualquier aplicación; el resto de usuarios del portal solo por la función
-- de acceso. El bloqueo y la desactivación se aplican a todos, siempre.

create or replace function public.portal_hook_token(event jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare
  v_uid uuid := (event->>'user_id')::uuid;
  v_met text := coalesce(event->>'authentication_method', '');
  u record;
begin
  select id, rol, activo, bloqueo_definitivo, bloqueado_hasta
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
  return event;
end $$;

-- Comprobación (sin sesión). Esperado: 1 fila con ok = true.
select p.proname, pg_get_functiondef(p.oid) like '%consulta_nacional%' as ok
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f' and p.proname = 'portal_hook_token';
