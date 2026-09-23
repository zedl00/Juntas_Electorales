-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 26
--  ADMINISTRACIÓN DE TELEGRAM DESDE EL PORTAL
-- ----------------------------------------------------------------
--  Los chats de Telegram se autorizaban por SQL. Aquí se añaden las
--  funciones para gestionarlos desde la pantalla de Usuarios, igual
--  que ya se hace con WhatsApp.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ.
-- ================================================================

set search_path = delegados, public;

create table if not exists delegados.bot_usuarios (
  chat_id     bigint primary key,
  cedula      text,
  descripcion text,
  rol         text not null default 'consulta' check (rol in ('consulta','admin')),
  activo      boolean not null default true,
  ultimo_uso  timestamptz,
  created_at  timestamptz not null default now()
);
alter table delegados.bot_usuarios add column if not exists ultimo_uso timestamptz;

alter table delegados.bot_usuarios enable row level security;
grant select, insert, update, delete on delegados.bot_usuarios to authenticated;
grant all on delegados.bot_usuarios to service_role;

drop policy if exists bu_admin on delegados.bot_usuarios;
create policy bu_admin on delegados.bot_usuarios
for all to authenticated using (delegados.portal_rol() = 'admin_sne')
with check (delegados.portal_rol() = 'admin_sne');

-- Listado
create or replace function delegados.portal_bot_tg_lista()
returns table (chat_id bigint, cedula text, descripcion text, rol text,
               activo boolean, ultimo_uso timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede ver los accesos autorizados';
  end if;
  return query
  select b.chat_id, b.cedula, b.descripcion, b.rol, b.activo, b.ultimo_uso, b.created_at
    from bot_usuarios b
   order by b.activo desc, b.ultimo_uso desc nulls last, b.descripcion;
end $$;

revoke all on function delegados.portal_bot_tg_lista() from public, anon;
grant execute on function delegados.portal_bot_tg_lista() to authenticated;

-- Alta
create or replace function delegados.portal_bot_tg_alta(
  p_chat bigint, p_cedula text default null, p_desc text default null, p_rol text default 'consulta')
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede autorizar accesos';
  end if;
  if p_chat is null then raise exception 'Falta el identificador de chat'; end if;
  insert into bot_usuarios (chat_id, cedula, descripcion, rol)
  values (p_chat, nullif(regexp_replace(coalesce(p_cedula,''),'\D','','g'),''), p_desc, coalesce(p_rol,'consulta'))
  on conflict (chat_id) do update
     set descripcion = excluded.descripcion, rol = excluded.rol, activo = true;
  perform portal_log('alta_bot_tg', 'telegram', p_chat::text, jsonb_build_object('rol', p_rol));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_bot_tg_alta(bigint,text,text,text) from public, anon;
grant execute on function delegados.portal_bot_tg_alta(bigint,text,text,text) to authenticated;

-- Activar / desactivar
create or replace function delegados.portal_bot_tg_estado(p_chat bigint, p_activo boolean)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  update bot_usuarios set activo = coalesce(p_activo, false) where chat_id = p_chat;
  if not found then raise exception 'Ese acceso no está registrado'; end if;
  perform portal_log(case when p_activo then 'bot_tg_activado' else 'bot_tg_revocado' end,
                     'telegram', p_chat::text, null);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_bot_tg_estado(bigint, boolean) from public, anon;
grant execute on function delegados.portal_bot_tg_estado(bigint, boolean) to authenticated;

-- Baja
create or replace function delegados.portal_bot_tg_baja(p_chat bigint)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  delete from bot_usuarios where chat_id = p_chat;
  perform portal_log('bot_tg_eliminado', 'telegram', p_chat::text, null);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_bot_tg_baja(bigint) from public, anon;
grant execute on function delegados.portal_bot_tg_baja(bigint) to authenticated;

notify pgrst, 'reload schema';
