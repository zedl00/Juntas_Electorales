-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 27
--  BITÁCORA COMPLETA DEL ASISTENTE (ambos canales)
-- ----------------------------------------------------------------
--  Las consultas por Telegram no quedaban registradas. Ahora ambos
--  canales pasan por una función de autorización que:
--    · verifica el identificador contra la lista de autorizados
--    · actualiza la marca de último uso
--    · registra la consulta en la bitácora con el comando usado
--
--  EJECUTAR COMPLETO. Requiere fase26.
-- ================================================================

set search_path = delegados, public;

-- ── Telegram: autorización + bitácora ──
create or replace function delegados.portal_bot_tg_auth(p_chat bigint, p_comando text default null)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare r record; v_uid uuid;
begin
  select * into r from bot_usuarios where chat_id = p_chat;
  if not found or not r.activo then
    insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (null, 'bot_no_autorizado', 'telegram', p_chat::text,
            jsonb_build_object('comando', p_comando));
    return jsonb_build_object('ok', false);
  end if;

  update bot_usuarios set ultimo_uso = now() where chat_id = p_chat;

  if r.cedula is not null then
    select id into v_uid from usuarios_territoriales where cedula = r.cedula;
  end if;

  insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
  values (v_uid, 'consulta_bot', 'telegram', p_chat::text,
          jsonb_build_object('canal','Telegram','comando', p_comando,
                             'rol', r.rol, 'quien', r.descripcion, 'cedula', r.cedula));

  return jsonb_build_object('ok', true, 'rol', r.rol,
                            'nombre', coalesce(r.descripcion, 'usuario autorizado'),
                            'cedula', r.cedula);
end $$;

revoke all on function delegados.portal_bot_tg_auth(bigint, text) from public, anon, authenticated;
grant execute on function delegados.portal_bot_tg_auth(bigint, text) to service_role;

-- ── WhatsApp: se añade el comando a la bitácora ──
create or replace function delegados.portal_bot_wa_auth(p_tel text, p_comando text default null)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  r record; v_uid uuid;
begin
  select * into r from bot_whatsapp where telefono = v_tel;
  if not found or not r.activo then
    insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (null, 'bot_no_autorizado', 'whatsapp', v_tel,
            jsonb_build_object('comando', p_comando));
    return jsonb_build_object('ok', false);
  end if;

  update bot_whatsapp set ultimo_uso = now() where telefono = v_tel;

  if r.cedula is not null then
    select id into v_uid from usuarios_territoriales where cedula = r.cedula;
  end if;

  insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
  values (v_uid, 'consulta_bot', 'whatsapp', v_tel,
          jsonb_build_object('canal','WhatsApp','comando', p_comando,
                             'rol', r.rol, 'quien', r.descripcion, 'cedula', r.cedula));

  return jsonb_build_object('ok', true, 'rol', r.rol,
                            'nombre', coalesce(r.descripcion, 'usuario autorizado'),
                            'cedula', r.cedula);
end $$;

revoke all on function delegados.portal_bot_wa_auth(text, text) from public, anon, authenticated;
grant execute on function delegados.portal_bot_wa_auth(text, text) to service_role;

notify pgrst, 'reload schema';
