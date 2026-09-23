-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 22 · BOT DE WHATSAPP (Meta Cloud API)
-- ----------------------------------------------------------------
--  Reutiliza las funciones de consulta ya creadas en la fase 5
--  (portal_bot_resumen, portal_bot_nivel, portal_bot_reset_pin):
--  son agnósticas del canal, solo cambia quién las invoca.
--
--  Añade el registro de números autorizados y la bitácora del canal.
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ.
-- ================================================================

set search_path = delegados, public;

-- ----------------------------------------------------------------
-- 1. Números de WhatsApp autorizados (control total de la Comisión)
-- ----------------------------------------------------------------
create table if not exists delegados.bot_whatsapp (
  telefono    text primary key,          -- formato internacional sin +, ej. 18095551234
  cedula      text,
  descripcion text,
  rol         text not null default 'consulta' check (rol in ('consulta','admin')),
  activo      boolean not null default true,
  ultimo_uso  timestamptz,
  created_at  timestamptz not null default now()
);

alter table delegados.bot_whatsapp enable row level security;
grant select on delegados.bot_whatsapp to authenticated;
grant all on delegados.bot_whatsapp to service_role;

drop policy if exists bw_admin on delegados.bot_whatsapp;
create policy bw_admin on delegados.bot_whatsapp
for all to authenticated using (delegados.portal_rol() = 'admin_sne')
with check (delegados.portal_rol() = 'admin_sne');

comment on table delegados.bot_whatsapp is
  'Números autorizados a consultar por WhatsApp. Alta y baja solo por la administración de la SNE.';

-- ----------------------------------------------------------------
-- 2. Autorización y registro de uso (una sola llamada del bot)
-- ----------------------------------------------------------------
create or replace function delegados.portal_bot_wa_auth(p_tel text)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare
  v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  r record;
begin
  select * into r from bot_whatsapp where telefono = v_tel;
  if not found or not r.activo then
    return jsonb_build_object('ok', false);
  end if;
  update bot_whatsapp set ultimo_uso = now() where telefono = v_tel;
  insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
  values (null, 'consulta_bot', 'whatsapp', v_tel,
          jsonb_build_object('rol', r.rol, 'descripcion', r.descripcion));
  return jsonb_build_object('ok', true, 'rol', r.rol, 'nombre', coalesce(r.descripcion, 'usuario autorizado'));
end $$;

revoke all on function delegados.portal_bot_wa_auth(text) from public, anon, authenticated;
grant execute on function delegados.portal_bot_wa_auth(text) to service_role;

-- ----------------------------------------------------------------
-- 3. Alta de números desde el portal (administración)
-- ----------------------------------------------------------------
create or replace function delegados.portal_bot_wa_alta(
  p_tel text, p_cedula text default null, p_desc text default null, p_rol text default 'consulta')
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v_tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede autorizar números';
  end if;
  if length(v_tel) < 10 then raise exception 'Número inválido: usa formato internacional, ej. 18095551234'; end if;
  insert into bot_whatsapp (telefono, cedula, descripcion, rol)
  values (v_tel, nullif(regexp_replace(coalesce(p_cedula,''),'\D','','g'),''), p_desc, coalesce(p_rol,'consulta'))
  on conflict (telefono) do update
     set descripcion = excluded.descripcion, rol = excluded.rol, activo = true;
  perform portal_log('alta_bot_wa', 'whatsapp', v_tel, jsonb_build_object('rol', p_rol));
  return jsonb_build_object('ok', true, 'telefono', v_tel);
end $$;

revoke all on function delegados.portal_bot_wa_alta(text,text,text,text) from public, anon;
grant execute on function delegados.portal_bot_wa_alta(text,text,text,text) to authenticated;

notify pgrst, 'reload schema';

-- ── USO ──
--  Autorizar un número (desde el SQL Editor o el portal):
--    select delegados.portal_bot_wa_alta('18095551234', '01200690764', 'Nestor Valdez · SNE', 'admin');
--    select delegados.portal_bot_wa_alta('18299876543', null, 'Coordinador Región Sur', 'consulta');
--  Revocar:
--    update delegados.bot_whatsapp set activo = false where telefono = '18095551234';
--  Ver quién ha consultado:
--    select telefono, descripcion, rol, ultimo_uso from delegados.bot_whatsapp order by ultimo_uso desc nulls last;
