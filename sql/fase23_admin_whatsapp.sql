-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 23
--  ADMINISTRACIÓN DE WHATSAPP DESDE EL PORTAL
-- ----------------------------------------------------------------
--  La fase 22 dejó la tabla de números autorizados con permiso de
--  solo lectura para los usuarios autenticados, de modo que dar de
--  alta o revocar exigía SQL. Aquí se otorgan los permisos que
--  faltaban (la política RLS sigue limitando todo a admin_sne) y se
--  añaden las funciones que usa la pantalla de administración.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase22.
-- ================================================================

set search_path = delegados, public;

grant select, insert, update, delete on delegados.bot_whatsapp to authenticated;

-- Listado para la pantalla de administración
create or replace function delegados.portal_bot_wa_lista()
returns table (telefono text, cedula text, descripcion text, rol text,
               activo boolean, ultimo_uso timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede ver los números autorizados';
  end if;
  return query
  select b.telefono, b.cedula, b.descripcion, b.rol, b.activo, b.ultimo_uso, b.created_at
    from bot_whatsapp b
   order by b.activo desc, b.ultimo_uso desc nulls last, b.descripcion;
end $$;

revoke all on function delegados.portal_bot_wa_lista() from public, anon;
grant execute on function delegados.portal_bot_wa_lista() to authenticated;

-- Activar / desactivar
create or replace function delegados.portal_bot_wa_estado(p_tel text, p_activo boolean)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede modificar los accesos';
  end if;
  update bot_whatsapp set activo = coalesce(p_activo, false) where telefono = v_tel;
  if not found then raise exception 'Ese número no está registrado'; end if;
  perform portal_log(case when p_activo then 'bot_wa_activado' else 'bot_wa_revocado' end,
                     'whatsapp', v_tel, null);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_bot_wa_estado(text, boolean) from public, anon;
grant execute on function delegados.portal_bot_wa_estado(text, boolean) to authenticated;

-- Eliminar por completo
create or replace function delegados.portal_bot_wa_baja(p_tel text)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede eliminar accesos';
  end if;
  delete from bot_whatsapp where telefono = v_tel;
  perform portal_log('bot_wa_eliminado', 'whatsapp', v_tel, null);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_bot_wa_baja(text) from public, anon;
grant execute on function delegados.portal_bot_wa_baja(text) to authenticated;

notify pgrst, 'reload schema';
