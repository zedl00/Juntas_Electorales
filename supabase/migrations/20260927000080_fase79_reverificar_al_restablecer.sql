-- fase79_reverificar_al_restablecer.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Hasta ahora la verificación de identidad con el padrón se pedía una sola vez
-- en la vida de la cuenta. Si la Comisión restablecía un PIN y ese PIN llegaba
-- a un teléfono equivocado, quien lo recibiera entraba sin verificación.
--
-- Nuevo parámetro en Seguridad del acceso: «Volver a verificar identidad al
-- restablecer el PIN» (activado por defecto). Cuando está activo, todo
-- restablecimiento de PIN (desde Gestión o desde el asistente de WhatsApp)
-- borra la verificación anterior y pone los intentos de identidad en cero:
-- en el siguiente ingreso la persona vuelve a responder con sus datos del padrón.
-- La confirmación de la SNE no se repite: el restablecimiento lo hizo la propia SNE.
--
-- Cómo se detecta el restablecimiento: las dos funciones de restablecer
-- (portal_reset_pin y portal_bot_reset_pin) ponen primer_acceso en true. El
-- disparador actúa solo en ese cambio (false → true), nunca cuando la persona
-- crea su PIN personal (true → false) ni en otras ediciones del usuario.

-- ── 1. Parámetro ──
alter table delegados.config_seguridad
  add column if not exists reverificar_al_reset boolean not null default true;

comment on column delegados.config_seguridad.reverificar_al_reset is
  'Al restablecer un PIN se borra la verificación de identidad: la persona la repite en el siguiente ingreso.';

-- ── 2. Disparador ──
create or replace function delegados.trg_ut_reverificar()
returns trigger language plpgsql security definer set search_path = delegados, public as $$
declare v_on boolean;
begin
  if new.primer_acceso and not coalesce(old.primer_acceso, false) then
    select coalesce(reverificar_al_reset, true) into v_on from config_seguridad where id;
    if coalesce(v_on, true) and old.verificado_padron_en is not null then
      new.verificado_padron_en := null;
      new.intentos_identidad   := 0;
      insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (auth.uid(), 'identidad_reiniciada', 'usuario', new.cedula,
              jsonb_build_object('nombre', new.nombre, 'motivo', 'reset_pin'));
    end if;
  end if;
  return new;
end $$;

drop trigger if exists ut_reverificar on delegados.usuarios_territoriales;
create trigger ut_reverificar
  before update of primer_acceso on delegados.usuarios_territoriales
  for each row execute function delegados.trg_ut_reverificar();

-- ── 3. Guardar la configuración (añade el parámetro) ──
create or replace function delegados.portal_config_seguridad_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
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
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con parametro = true y disparador = true.
select (select reverificar_al_reset from delegados.config_seguridad where id) as parametro,
       exists (select 1 from pg_trigger where tgname = 'ut_reverificar' and not tgisinternal) as disparador;
