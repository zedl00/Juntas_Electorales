-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 5 · GESTIÓN DE USUARIOS
--  Restablecimiento de PIN en un clic (solo administración SNE)
-- ----------------------------------------------------------------
--  · Ejecutar DESPUÉS de fase1, fase2 y fase4. Idempotente.
--  · La administración genera un PIN provisional desde el portal;
--    el usuario entra con él y el sistema le exige crear el suyo.
--  · Cada restablecimiento queda en la bitácora (quién, a quién).
-- ================================================================

set search_path = delegados, public;

create or replace function delegados.portal_reset_pin(p_cedula text, p_pin text)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public, extensions as $$
declare
  v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
  v_uid uuid;
  v_nombre text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede restablecer un PIN';
  end if;
  if length(coalesce(p_pin,'')) < 6 then
    raise exception 'El PIN provisional debe tener al menos 6 caracteres';
  end if;

  select u.id, u.nombre into v_uid, v_nombre
    from usuarios_territoriales u
   where regexp_replace(u.cedula, '\D', '', 'g') = v_ced;
  if v_uid is null then
    raise exception 'No existe un usuario del portal con esa cédula';
  end if;
  if v_uid = auth.uid() then
    raise exception 'Para tu propia cuenta usa el cambio de PIN en Mi cuenta';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_uid
     and email like '%@delegadosfp.com';
  if not found then
    raise exception 'Esta cuenta no usa PIN (acceso institucional): no se puede restablecer desde aquí';
  end if;

  update usuarios_territoriales set primer_acceso = true where id = v_uid;

  perform portal_log('reset_pin', 'usuario', v_ced, jsonb_build_object('nombre', v_nombre));

  return jsonb_build_object('ok', true, 'nombre', v_nombre, 'cedula', v_ced);
end $$;

revoke all on function delegados.portal_reset_pin(text, text) from public, anon;
grant execute on function delegados.portal_reset_pin(text, text) to authenticated;

notify pgrst, 'reload schema';
