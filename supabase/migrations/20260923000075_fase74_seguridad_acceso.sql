-- fase74_seguridad_acceso.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Decisión de la Comisión (23 sep 2026): seguridad del acceso en cuatro capas,
-- cada una con su interruptor en Gestión → Configuración → Seguridad del acceso.
--
--  A. Bloqueo por intentos fallidos (gancho de verificación de PIN de la base):
--     · a partir de N1 fallos (3) el mensaje avisa cuántos intentos quedan;
--     · al llegar a N2 fallos (5) la cuenta se bloquea M minutos (15);
--     · pasado el bloqueo vuelve a tener N2 intentos; si los agota otra vez,
--       bloqueo DEFINITIVO: solo la administración lo levanta desde la lista de
--       usuarios bloqueados. Todo en Gestión → Usuarios.
--  B. Verificación de identidad contra el padrón en el primer acceso:
--     fecha de nacimiento y municipio donde vota. Tres fallos = bloqueo definitivo.
--  C. PIN inicial de un solo uso con caducidad (72 h por defecto).
--  D. Confirmación de la SNE: cada primer ingreso queda «por confirmar»; hasta
--     entonces la persona consulta pero no registra.
--  Además: «¿Olvidaste tu PIN?» vuelve a funcionar (solicitud anónima con
--  control de duplicados) y bandeja de envío de accesos por WhatsApp.

-- ── 1. Configuración ──
alter table delegados.config_seguridad add column if not exists bloqueo_activo     boolean not null default true;
alter table delegados.config_seguridad add column if not exists intentos_aviso     integer not null default 3;
alter table delegados.config_seguridad add column if not exists intentos_bloqueo   integer not null default 5;
alter table delegados.config_seguridad add column if not exists bloqueo_minutos    integer not null default 15;
alter table delegados.config_seguridad add column if not exists verificar_padron   boolean not null default true;
alter table delegados.config_seguridad add column if not exists pin_caduca_horas   integer not null default 72;
alter table delegados.config_seguridad add column if not exists confirmar_sne      boolean not null default true;

-- ── 2. Estado por usuario ──
alter table delegados.usuarios_territoriales add column if not exists intentos_fallidos    integer not null default 0;
alter table delegados.usuarios_territoriales add column if not exists bloqueado_hasta      timestamptz;
alter table delegados.usuarios_territoriales add column if not exists bloqueos             integer not null default 0;
alter table delegados.usuarios_territoriales add column if not exists bloqueo_definitivo   boolean not null default false;
alter table delegados.usuarios_territoriales add column if not exists bloqueo_motivo       text;
alter table delegados.usuarios_territoriales add column if not exists intentos_identidad   integer not null default 0;
alter table delegados.usuarios_territoriales add column if not exists verificado_padron_en timestamptz;
alter table delegados.usuarios_territoriales add column if not exists primer_ingreso_en    timestamptz;
alter table delegados.usuarios_territoriales add column if not exists primer_ingreso_agente text;
alter table delegados.usuarios_territoriales add column if not exists confirmado_sne_por   text;
alter table delegados.usuarios_territoriales add column if not exists confirmado_sne_en    timestamptz;

alter table delegados.usuarios_pin_inicial add column if not exists generado_en timestamptz default now();
alter table delegados.usuarios_pin_inicial add column if not exists caduca_en   timestamptz;
alter table delegados.usuarios_pin_inicial add column if not exists enviado_por text;
alter table delegados.usuarios_pin_inicial add column if not exists enviado_en  timestamptz;

-- Todo PIN inicial nuevo o regenerado nace con fecha de caducidad
create or replace function delegados.trg_pin_inicial_caduca()
returns trigger language plpgsql security definer set search_path = delegados, public as $$
declare v_h integer;
begin
  if tg_op = 'INSERT' or new.pin is distinct from old.pin then
    select coalesce(pin_caduca_horas, 72) into v_h from config_seguridad where id;
    new.generado_en := now();
    new.caduca_en   := now() + make_interval(hours => coalesce(v_h, 72));
    new.entregado   := false;
    new.enviado_por := null; new.enviado_en := null;
  end if;
  return new;
end $$;
drop trigger if exists upi_caduca on delegados.usuarios_pin_inicial;
create trigger upi_caduca before insert or update on delegados.usuarios_pin_inicial
  for each row execute function delegados.trg_pin_inicial_caduca();
update delegados.usuarios_pin_inicial
   set caduca_en = coalesce(generado_en, now()) + interval '72 hours'
 where caduca_en is null;

-- ── 3. El rol solo existe si la cuenta no está bloqueada (lo aplican TODAS las políticas) ──
create or replace function delegados.portal_rol()
returns text language sql stable security definer set search_path = delegados, public as $$
  select rol from usuarios_territoriales
   where id = auth.uid() and activo
     and not bloqueo_definitivo
     and (bloqueado_hasta is null or bloqueado_hasta < now())
$$;

-- Registrar solo tras la confirmación de la SNE (si está activada) y la verificación del padrón (si está activada)
create or replace function delegados.portal_puede_registrar()
returns boolean language sql stable security definer set search_path = delegados, public as $$
  select coalesce(u.puede_registrar, u.rol in ('enc_electoral','admin_sne'))
         and (u.rol = 'admin_sne'
              or ((not coalesce(c.confirmar_sne, true) or u.confirmado_sne_en is not null)
                  and (not coalesce(c.verificar_padron, true) or u.verificado_padron_en is not null)))
    from usuarios_territoriales u, config_seguridad c
   where u.id = auth.uid() and u.activo and c.id
$$;

-- ── 4. Gancho de verificación de PIN (lo llama Supabase Auth en cada intento) ──
create or replace function public.portal_hook_verificacion_pin(event jsonb)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare
  v_uid uuid := (event->>'user_id')::uuid;
  v_ok  boolean := coalesce((event->>'valid')::boolean, false);
  u record; c record; v_restan integer; v_min integer;
begin
  select * into c from delegados.config_seguridad where id;
  select * into u from delegados.usuarios_territoriales where id = v_uid;
  if u.id is null then return jsonb_build_object('decision', 'continue'); end if;   -- cuentas de otras apps

  if u.bloqueo_definitivo then
    return jsonb_build_object('decision', 'reject',
      'message', 'Tu acceso está bloqueado. Comunícate con la Comisión para habilitarlo.');
  end if;
  if u.bloqueado_hasta is not null and u.bloqueado_hasta > now() then
    v_min := greatest(1, ceil(extract(epoch from (u.bloqueado_hasta - now())) / 60))::integer;
    return jsonb_build_object('decision', 'reject',
      'message', 'Acceso bloqueado temporalmente por intentos fallidos. Vuelve a intentarlo en ' || v_min || ' minuto(s).');
  end if;

  if v_ok then
    -- PIN inicial vencido
    if u.primer_acceso and exists (select 1 from delegados.usuarios_pin_inicial p
                                    where p.cedula = u.cedula and p.caduca_en is not null and p.caduca_en < now()) then
      insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (u.id, 'pin_vencido', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre));
      return jsonb_build_object('decision', 'reject',
        'message', 'Tu PIN inicial venció. Pide uno nuevo con «¿Olvidaste tu PIN?» o a la Comisión.');
    end if;
    update delegados.usuarios_territoriales set intentos_fallidos = 0 where id = u.id;
    return jsonb_build_object('decision', 'continue');
  end if;

  -- PIN incorrecto
  if not coalesce(c.bloqueo_activo, true) then return jsonb_build_object('decision', 'continue'); end if;

  update delegados.usuarios_territoriales set intentos_fallidos = intentos_fallidos + 1 where id = u.id
    returning intentos_fallidos into v_restan;

  if v_restan >= coalesce(c.intentos_bloqueo, 5) then
    if u.bloqueos >= 1 then
      update delegados.usuarios_territoriales
         set bloqueo_definitivo = true, bloqueo_motivo = 'Intentos fallidos repetidos', intentos_fallidos = 0
       where id = u.id;
      insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
      values (u.id, 'bloqueo_definitivo', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'motivo', 'intentos fallidos'));
      return jsonb_build_object('decision', 'reject',
        'message', 'Acceso bloqueado por intentos fallidos repetidos. Solo la Comisión puede habilitarlo.');
    end if;
    update delegados.usuarios_territoriales
       set bloqueado_hasta = now() + make_interval(mins => coalesce(c.bloqueo_minutos, 15)),
           bloqueos = bloqueos + 1, intentos_fallidos = 0
     where id = u.id;
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (u.id, 'bloqueo_temporal', 'usuario', u.cedula, jsonb_build_object('nombre', u.nombre, 'minutos', coalesce(c.bloqueo_minutos, 15)));
    return jsonb_build_object('decision', 'reject',
      'message', 'Demasiados intentos fallidos. Acceso bloqueado por ' || coalesce(c.bloqueo_minutos, 15) || ' minutos.');
  end if;

  if v_restan >= coalesce(c.intentos_aviso, 3) then
    return jsonb_build_object('decision', 'reject',
      'message', 'PIN incorrecto. Te quedan ' || (coalesce(c.intentos_bloqueo, 5) - v_restan) || ' intento(s) antes del bloqueo.');
  end if;
  return jsonb_build_object('decision', 'continue');   -- Auth responde «cédula o PIN incorrectos»
end $$;
revoke execute on function public.portal_hook_verificacion_pin(jsonb) from public, anon, authenticated;
grant  execute on function public.portal_hook_verificacion_pin(jsonb) to supabase_auth_admin;
grant  usage on schema public to supabase_auth_admin;

-- ── 5. Lista de bloqueados y desbloqueo (administración) ──
create or replace function delegados.portal_bloqueados()
returns table(id uuid, cedula text, nombre text, rol text, telefono text, tipo text, hasta timestamptz,
              motivo text, intentos integer, bloqueos integer)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query
  select u.id, u.cedula::text, u.nombre::text, u.rol::text, u.telefono::text,
         case when u.bloqueo_definitivo then 'definitivo' else 'temporal' end::text,
         u.bloqueado_hasta, u.bloqueo_motivo::text, u.intentos_fallidos, u.bloqueos
    from usuarios_territoriales u
   where u.bloqueo_definitivo or (u.bloqueado_hasta is not null and u.bloqueado_hasta > now())
   order by u.bloqueo_definitivo desc, u.bloqueado_hasta desc nulls last;
end $$;

create or replace function delegados.portal_desbloquear(p_id uuid)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_ced text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  update usuarios_territoriales
     set bloqueo_definitivo = false, bloqueado_hasta = null, bloqueos = 0,
         intentos_fallidos = 0, intentos_identidad = 0, bloqueo_motivo = null
   where id = p_id returning cedula into v_ced;
  if v_ced is null then return jsonb_build_object('ok', false, 'msg', 'Usuario no encontrado.'); end if;
  perform portal_log('desbloqueo', 'usuario', v_ced, null);
  return jsonb_build_object('ok', true);
end $$;

-- ── 6. Verificación de identidad contra el padrón (primer acceso) ──
create or replace function delegados.portal_verificar_identidad(p_fecha_nac date, p_municipio_id integer)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare u record; pa record; v_mun integer; v_ok boolean; v_int integer; c record;
begin
  select * into u from usuarios_territoriales where id = auth.uid() and activo;
  if u.id is null then raise exception 'Acceso no autorizado'; end if;
  select * into c from config_seguridad where id;
  if u.verificado_padron_en is not null then return jsonb_build_object('ok', true, 'ya', true); end if;

  select pa2.fecha_nacimiento, pa2.id_municipio, pa2.lugar_votacion into pa
    from public.jce_padron pa2 where pa2.cedula = u.cedula and pa2.activo limit 1;
  if pa.fecha_nacimiento is null then
    -- No está en el padrón cargado: no se puede contrastar; queda para confirmación de la SNE
    update usuarios_territoriales set verificado_padron_en = now() where id = u.id;
    perform portal_log('identidad_sin_padron', 'usuario', u.cedula, null);
    return jsonb_build_object('ok', true, 'sin_padron', true);
  end if;

  select x.municipio_id into v_mun from delegados._unidades_jce x where x.jce_id = pa.id_municipio limit 1;
  v_ok := (pa.fecha_nacimiento = p_fecha_nac)
          and (pa.lugar_votacion = 'E' or v_mun is null or v_mun = p_municipio_id);

  if v_ok then
    update usuarios_territoriales set verificado_padron_en = now(), intentos_identidad = 0 where id = u.id;
    perform portal_log('identidad_verificada', 'usuario', u.cedula, null);
    return jsonb_build_object('ok', true);
  end if;

  update usuarios_territoriales set intentos_identidad = intentos_identidad + 1 where id = u.id
    returning intentos_identidad into v_int;
  if v_int >= 3 then
    update usuarios_territoriales
       set bloqueo_definitivo = true, bloqueo_motivo = 'No superó la verificación de identidad' where id = u.id;
    perform portal_log('bloqueo_definitivo', 'usuario', u.cedula, jsonb_build_object('motivo', 'identidad'));
    return jsonb_build_object('ok', false, 'bloqueado', true,
      'msg', 'Los datos no coinciden con el padrón. Tu acceso quedó bloqueado; comunícate con la Comisión.');
  end if;
  perform portal_log('identidad_fallida', 'usuario', u.cedula, jsonb_build_object('intento', v_int));
  return jsonb_build_object('ok', false, 'restantes', 3 - v_int,
    'msg', 'Los datos no coinciden con el padrón. Te quedan ' || (3 - v_int) || ' intento(s).');
end $$;

-- ── 7. Confirmación de la SNE ──
create or replace function delegados.portal_accesos_por_confirmar()
returns table(id uuid, cedula text, nombre text, rol text, telefono text, territorio text,
              primer_ingreso_en timestamptz, agente text, verificado boolean)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query
  select u.id, u.cedula::text, u.nombre::text, u.rol::text, u.telefono::text,
         coalesce(d.nombre || ' · ' || m.nombre, m.nombre, p.nombre, '')::text,
         u.primer_ingreso_en, u.primer_ingreso_agente::text, u.verificado_padron_en is not null
    from usuarios_territoriales u
    left join portal_metas_municipio m on m.municipio_id = u.municipio_id
    left join portal_distritos d on d.jce_id = u.jce_id and d.municipio_id = u.municipio_id
    left join public.provincias p on p.id = u.provincia_id
   where u.activo and u.rol <> 'admin_sne'
     and u.primer_ingreso_en is not null and u.confirmado_sne_en is null
   order by u.primer_ingreso_en desc;
end $$;

create or replace function delegados.portal_confirmar_acceso(p_id uuid, p_ok boolean, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_ced text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  if p_ok then
    update usuarios_territoriales set confirmado_sne_por = v_nom, confirmado_sne_en = now()
     where id = p_id returning cedula into v_ced;
    perform portal_log('acceso_confirmado', 'usuario', v_ced, jsonb_build_object('nota', p_nota));
  else
    update usuarios_territoriales
       set activo = false, bloqueo_motivo = coalesce(p_nota, 'Identidad no confirmada por la SNE')
     where id = p_id returning cedula into v_ced;
    perform portal_log('acceso_rechazado', 'usuario', v_ced, jsonb_build_object('nota', p_nota));
  end if;
  if v_ced is null then return jsonb_build_object('ok', false, 'msg', 'Usuario no encontrado.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ── 8. Perfil: registra el primer ingreso y expone el estado de las capas ──
drop function if exists delegados.portal_mi_perfil();
create or replace function delegados.portal_mi_perfil(p_agente text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v jsonb; c record;
begin
  update usuarios_territoriales set ultimo_acceso = now() where id = auth.uid();
  update usuarios_territoriales
     set primer_ingreso_en = now(), primer_ingreso_agente = left(p_agente, 300)
   where id = auth.uid() and primer_ingreso_en is null;
  select * into c from config_seguridad where id;

  select jsonb_build_object(
    'id', u.id, 'cedula', u.cedula, 'nombre', u.nombre, 'telefono', u.telefono,
    'rol', u.rol, 'activo', u.activo, 'primer_acceso', u.primer_acceso,
    'acuse_instructivo', u.acuse_instructivo,
    'ver_distritos', u.ver_distritos,
    'puede_registrar', delegados.portal_puede_registrar(),
    'puede_imprimir', coalesce(u.puede_imprimir,
        u.rol in ('presidente','secretario_general','enc_electoral',
                  'admin_sne','consulta_nacional','supervisor_provincial','coordinador_regional')),
    'municipio_id', u.municipio_id, 'municipio', m.nombre,
    'jce_id', u.jce_id, 'distrito', d.nombre,
    'junta', m.junta_nombre, 'tipo_territorio', m.tipo,
    'provincia_id', coalesce(u.provincia_id, m.provincia_id),
    'provincia', coalesce(p.nombre, m.provincia_nombre),
    'region', coalesce(u.region, v2.macroregion),
    'colegios', coalesce(d.colegios, v2.colegios),
    'meta', coalesce(d.meta, v2.meta),
    'electores', coalesce(d.electores, v2.electores),
    /* Capas de seguridad (fase 74) */
    'verificar_identidad', coalesce(c.verificar_padron, true) and u.verificado_padron_en is null and u.rol <> 'admin_sne',
    'confirmacion_pendiente', coalesce(c.confirmar_sne, true) and u.confirmado_sne_en is null and u.rol <> 'admin_sne',
    'bloqueo_definitivo', u.bloqueo_definitivo
  ) into v
  from usuarios_territoriales u
  left join municipios m  on m.id = u.municipio_id
  left join provincias p  on p.id = coalesce(u.provincia_id, m.provincia_id)
  left join portal_metas_municipio v2 on v2.municipio_id = u.municipio_id
  left join portal_distritos d on d.municipio_id = u.municipio_id and d.jce_id = u.jce_id
  where u.id = auth.uid();

  if v is not null then
    perform portal_log('acceso', 'sesion', null, jsonb_build_object('rol', v->>'rol'));
  end if;
  return v;
end $$;

-- ── 9. «¿Olvidaste tu PIN?»: solicitud anónima con control de duplicados ──
create or replace function public.portal_solicitar_pin(p_cedula text)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
begin
  if length(v_ced) <> 11 then
    return jsonb_build_object('ok', false, 'mensaje', 'Escribe la cédula completa, 11 dígitos.');
  end if;
  -- Misma respuesta exista o no la cuenta: no se revela quién es usuario
  if exists (select 1 from delegados.usuarios_territoriales u where u.cedula = v_ced and u.activo)
     and not exists (select 1 from delegados.solicitudes_pin s where s.cedula = v_ced and s.estado = 'pendiente') then
    insert into delegados.solicitudes_pin (cedula, estado) values (v_ced, 'pendiente');
    insert into delegados.eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
    values (null, 'solicitud_pin', 'usuario', v_ced, null);
  end if;
  return jsonb_build_object('ok', true,
    'mensaje', 'Solicitud recibida. Si la cédula tiene acceso al portal, la Comisión te enviará un PIN nuevo por WhatsApp.');
end $$;
revoke execute on function public.portal_solicitar_pin(text) from public;
grant  execute on function public.portal_solicitar_pin(text) to anon, authenticated;

-- ── 10. Bandeja de envío de accesos ──
create or replace function delegados.portal_pines_por_enviar()
returns table(cedula text, nombre text, telefono text, rol text, territorio text, pin text,
              generado_en timestamptz, caduca_en timestamptz, vencido boolean)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query
  select p.cedula::text, p.nombre::text, coalesce(u.telefono, p.telefono)::text, p.rol::text, p.territorio::text, p.pin::text,
         p.generado_en, p.caduca_en, (p.caduca_en is not null and p.caduca_en < now())
    from usuarios_pin_inicial p
    left join usuarios_territoriales u on u.cedula = p.cedula
   where not coalesce(p.entregado, false)
     and (u.id is null or (u.activo and u.primer_acceso))
   order by p.territorio, p.nombre;
end $$;

create or replace function delegados.portal_pin_entregado(p_cedula text)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  update usuarios_pin_inicial set entregado = true, enviado_por = v_nom, enviado_en = now() where cedula = v_ced;
  perform portal_log('pin_enviado', 'usuario', v_ced, jsonb_build_object('canal', 'whatsapp'));
  return jsonb_build_object('ok', true);
end $$;

-- ── 11. Guardar la configuración de seguridad (todas las capas) ──
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
    pin_caduca_horas = coalesce((p->>'pin_caduca_horas')::integer, pin_caduca_horas),
    confirmar_sne    = coalesce((p->>'confirmar_sne')::boolean, confirmar_sne),
    actualizado_por  = v_nom, actualizado_en = now()
  where id;
  if (select captcha_activo and captcha_site_key is null from config_seguridad where id) then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  perform portal_log('config_seguridad', 'configuracion', null, p);
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function delegados.portal_config_seguridad_guardar(jsonb) from public, anon;
grant  execute on function delegados.portal_config_seguridad_guardar(jsonb) to authenticated;

-- Comprobación (sin sesión). Esperado: 1 fila con las siete columnas de configuración.
select bloqueo_activo, intentos_aviso, intentos_bloqueo, bloqueo_minutos, verificar_padron, pin_caduca_horas, confirmar_sne
  from delegados.config_seguridad where id;
