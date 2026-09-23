-- fase67_traslados_bloquear_y_permisos.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Decisiones de la Comisión (23 sep 2026):
--  1. Qué pasa cuando un registro excede el alcance configurado pasa a tener
--     tres opciones: permitir sin trámite · requerir autorización de la SNE ·
--     bloquear. Antes solo había las dos primeras (casilla «requiere autorización»).
--  2. El límite del encargado electoral (solo registra a quien vota en su
--     municipio) pasa a ser un parámetro visible, activado por defecto.
--  3. Asignar y mover colegio: solo la administración en todo el país, y en su
--     municipio el encargado o quien tenga permiso de registrar. Antes cualquier
--     usuario con sesión podía hacerlo (hueco de seguridad).

-- ── 1. Configuración ──
alter table delegados.config_traslados add column if not exists excede_accion text;
alter table delegados.config_traslados add column if not exists encargado_solo_municipio boolean;
update delegados.config_traslados
   set excede_accion = case when requiere_autorizacion then 'autorizar' else 'permitir' end
 where excede_accion is null;
update delegados.config_traslados set encargado_solo_municipio = true where encargado_solo_municipio is null;
alter table delegados.config_traslados alter column excede_accion set default 'autorizar';
alter table delegados.config_traslados alter column encargado_solo_municipio set default true;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'config_traslados_excede_accion_chk') then
    alter table delegados.config_traslados
      add constraint config_traslados_excede_accion_chk check (excede_accion in ('permitir','autorizar','bloquear'));
  end if;
end $$;

-- Guardar (la versión antigua con dos parámetros se conserva por compatibilidad)
create or replace function delegados.portal_config_traslados_set(p_alcance text, p_excede text, p_encargado_solo boolean)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede cambiar esta configuración';
  end if;
  if p_alcance not in ('colegio','municipio','provincia','libre') then
    raise exception 'Alcance no válido: %', p_alcance;
  end if;
  if p_excede not in ('permitir','autorizar','bloquear') then
    raise exception 'Acción no válida: %', p_excede;
  end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();

  update config_traslados
     set alcance = p_alcance,
         excede_accion = p_excede,
         requiere_autorizacion = (p_excede = 'autorizar'),   -- se mantiene en sincronía
         encargado_solo_municipio = coalesce(p_encargado_solo, true),
         actualizado = now(), actualizado_por = v_nom
   where id;

  perform portal_log('config_traslados', 'configuracion', null,
    jsonb_build_object('alcance', p_alcance, 'excede_accion', p_excede, 'encargado_solo_municipio', p_encargado_solo));

  return jsonb_build_object('ok', true);
end $$;
revoke execute on function delegados.portal_config_traslados_set(text, text, boolean) from public;
grant  execute on function delegados.portal_config_traslados_set(text, text, boolean) to authenticated;

-- ── 2. Evaluación del traslado con las tres acciones ──
create or replace function delegados.portal_evaluar_traslado(p_colegio_padron bigint, p_municipio_destino integer, p_jce_destino integer default null)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_alcance text; v_excede text;
  v_mun integer; v_jce integer; v_prov integer;
  v_rec text; v_col text; v_cod text;
  v_prov_dst integer;
  v_nivel text; v_peso integer; v_tope integer;
  v_permitido boolean; v_estado text;
  v_alcance_txt text;
begin
  select alcance, coalesce(excede_accion, case when requiere_autorizacion then 'autorizar' else 'permitir' end)
    into v_alcance, v_excede
    from config_traslados where id;

  select d.municipio_id, d.jce_id, d.provincia_id,
         coalesce(d.recinto_desc, 'Recinto ' || coalesce(d.codigo_recinto,'')),
         coalesce(d.codigo_colegio,'') ||
           case when d.colegio_desc is not null then ' — ' || d.colegio_desc else '' end,
         d.codigo_colegio
    into v_mun, v_jce, v_prov, v_rec, v_col, v_cod
    from portal_colegio_detalle d
   where d.id_colegio = p_colegio_padron
   limit 1;

  if v_mun is null then
    return jsonb_build_object('nivel', null, 'estado', 'no_aplica', 'permitido', true,
      'msg', 'No fue posible localizar el colegio del padrón.');
  end if;

  select m.provincia_id into v_prov_dst
    from portal_metas_municipio m where m.municipio_id = p_municipio_destino;

  v_nivel := case
    when v_mun = p_municipio_destino
         and (p_jce_destino is null or v_jce = p_jce_destino) then 'mismo_colegio'
    when v_mun = p_municipio_destino then 'mismo_municipio'
    when v_prov = v_prov_dst         then 'misma_provincia'
    else 'otra_provincia' end;

  v_peso := case v_nivel
    when 'mismo_colegio' then 0 when 'mismo_distrito' then 1
    when 'mismo_municipio' then 2 when 'misma_provincia' then 3 else 4 end;

  v_tope := case v_alcance
    when 'colegio' then 0 when 'municipio' then 2
    when 'provincia' then 3 else 4 end;

  v_permitido := v_peso <= v_tope;

  v_alcance_txt := case v_alcance
    when 'colegio' then 'su propio colegio' when 'municipio' then 'su municipio'
    when 'provincia' then 'su provincia' else 'cualquier territorio' end;

  v_estado := case
    when v_nivel = 'mismo_colegio' then 'no_aplica'
    when v_permitido then 'permitido'
    when v_excede = 'autorizar' then 'pendiente'
    when v_excede = 'bloquear' then 'bloqueado'
    else 'permitido' end;

  return jsonb_build_object(
    'nivel', v_nivel,
    'estado', v_estado,
    'permitido', v_estado in ('no_aplica','permitido'),
    'requiere_autorizacion', v_estado = 'pendiente',
    'bloqueado', v_estado = 'bloqueado',
    'alcance_configurado', v_alcance,
    'excede_accion', v_excede,
    'vota_municipio_id', v_mun,
    'vota_jce_id', v_jce,
    'vota_provincia_id', v_prov,
    'vota_recinto', v_rec,
    'vota_colegio', v_col,
    'msg', case
      when v_nivel = 'mismo_colegio' then null
      when v_permitido then 'Traslado dentro del alcance permitido.'
      when v_excede = 'autorizar' then 'Excede el alcance permitido: quedará pendiente de autorización de la SNE.'
      when v_excede = 'bloquear' then 'Está registrando fuera de ' || v_alcance_txt || '. La persona debe registrarse en su mismo territorio.'
      else 'Excede el alcance permitido, pero la configuración no exige autorización.' end);
end $$;

-- ── 3. Disparador: bloqueo configurado y límite del encargado parametrizado ──
create or replace function delegados.trg_p28_control_colegio()
returns trigger language plpgsql security definer set search_path = delegados, public as $$
declare
  v_admin boolean := coalesce(delegados.portal_rol() = 'admin_sne', false);
  v_sin_sesion boolean := auth.uid() is null;      -- scripts desde el editor SQL
  v_ced text := regexp_replace(coalesce(new.cedula, ''), '\D', '', 'g');
  v_fmt text;
  r record; v_ev jsonb;
begin
  -- ── Columnas reservadas a la administración ──
  if tg_op = 'UPDATE' and not (v_admin or v_sin_sesion) then
    if (new.cedula, new.nombres, new.apellido1, new.apellido2, new.municipio_id, new.numero_formulario,
        new.id_colegio_padron, new.codigo_colegio, new.colegio_desc, new.codigo_recinto, new.recinto_nombre,
        new.circunscripcion, new.lugar_votacion, new.municipio_padron_id, new.jce_padron_id,
        new.provincia_padron_id, new.recinto_padron_desc, new.colegio_padron_desc,
        new.traslado_nivel, new.traslado_estado, new.autorizado_por, new.traslado_resuelto_por,
        new.traslado_resuelto_en, new.traslado_nota, new.colegio_solicitado,
        new.sello_hash, new.sello_anterior, new.sello_at, new.registrado_por, new.validado_por, new.created_at)
       is distinct from
       (old.cedula, old.nombres, old.apellido1, old.apellido2, old.municipio_id, old.numero_formulario,
        old.id_colegio_padron, old.codigo_colegio, old.colegio_desc, old.codigo_recinto, old.recinto_nombre,
        old.circunscripcion, old.lugar_votacion, old.municipio_padron_id, old.jce_padron_id,
        old.provincia_padron_id, old.recinto_padron_desc, old.colegio_padron_desc,
        old.traslado_nivel, old.traslado_estado, old.autorizado_por, old.traslado_resuelto_por,
        old.traslado_resuelto_en, old.traslado_nota, old.colegio_solicitado,
        old.sello_hash, old.sello_anterior, old.sello_at, old.registrado_por, old.validado_por, old.created_at)
    then
      raise exception 'Ese dato solo lo cambia la administración de la SNE';
    end if;
    if old.traslado_estado = 'rechazado' and new.colegio_asignado is not null
       and new.colegio_asignado is distinct from old.colegio_asignado then
      raise exception 'Traslado rechazado por la SNE: no se le puede asignar colegio en este territorio';
    end if;
  end if;

  if tg_op = 'INSERT' then
    -- ── Datos del padrón: de la Junta, no del cliente ──
    r := null;
    if length(v_ced) >= 8 then
      select pa.id_colegio, pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion, pa.lugar_votacion,
             c.descripcion as colegio_desc, rc.descripcion as recinto_desc
        into r
        from public.jce_padron pa
        left join public.jce_colegio c  on c.id_colegio = pa.id_colegio
        left join public.jce_recinto rc on rc.id = c.id_recinto
       where pa.cedula = v_ced and pa.activo limit 1;
      if not found and length(v_ced) = 11 then
        v_fmt := substr(v_ced,1,3) || '-' || substr(v_ced,4,7) || '-' || substr(v_ced,11,1);
        select pa.id_colegio, pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion, pa.lugar_votacion,
               c.descripcion as colegio_desc, rc.descripcion as recinto_desc
          into r
          from public.jce_padron pa
          left join public.jce_colegio c  on c.id_colegio = pa.id_colegio
          left join public.jce_recinto rc on rc.id = c.id_recinto
         where pa.cedula = v_fmt and pa.activo limit 1;
      end if;
    end if;

    if r.id_colegio is not null then
      new.id_colegio_padron := r.id_colegio;
      new.codigo_colegio    := r.codigo_colegio;
      new.codigo_recinto    := r.codigo_recinto;
      new.circunscripcion   := r.codigo_circunscripcion;
      new.lugar_votacion    := r.lugar_votacion;
      new.colegio_desc      := r.colegio_desc;
      new.recinto_nombre    := r.recinto_desc;
    else
      new.id_colegio_padron := null;             -- registro manual: sin datos de padrón
    end if;

    -- ── Traslado: lo calcula la base con la configuración vigente ──
    -- Oficinas del exterior (OCLEE): la demarcación no aplica; se registra sin traslado (fase 66).
    if new.id_colegio_padron is not null and not exists (
         select 1 from portal_metas_municipio m
          where m.municipio_id = new.municipio_id and coalesce(m.tipo,'') = 'OCLEE') then
      v_ev := delegados.portal_evaluar_traslado(new.id_colegio_padron::bigint, new.municipio_id, null);
      new.traslado_nivel      := v_ev->>'nivel';
      new.traslado_estado     := coalesce(v_ev->>'estado', 'no_aplica');
      new.fuera_de_colegio    := coalesce(new.traslado_nivel, 'mismo_colegio') <> 'mismo_colegio';
      new.municipio_padron_id := (v_ev->>'vota_municipio_id')::integer;
      new.jce_padron_id       := (v_ev->>'vota_jce_id')::integer;
      new.provincia_padron_id := (v_ev->>'vota_provincia_id')::integer;
      new.recinto_padron_desc := v_ev->>'vota_recinto';
      new.colegio_padron_desc := v_ev->>'vota_colegio';
    else
      new.traslado_nivel := null; new.traslado_estado := 'no_aplica'; new.fuera_de_colegio := false;
      new.municipio_padron_id := null; new.jce_padron_id := null; new.provincia_padron_id := null;
      new.recinto_padron_desc := null; new.colegio_padron_desc := null;
    end if;
    -- ── Bloqueo configurado: excede el alcance y la Comisión decidió no permitirlo (fase 67) ──
    if new.traslado_estado = 'bloqueado' then
      raise exception 'Está registrando fuera del alcance permitido (%). La persona debe registrarse en su mismo territorio.',
        coalesce(v_ev->>'alcance_configurado', 'municipio');
    end if;

    -- ── Límite del encargado: solo registra a quien vota en su propio municipio (fases 64 y 67, parametrizado) ──
    if not (v_admin or v_sin_sesion)
       and coalesce((select c.encargado_solo_municipio from config_traslados c where c.id), true)
       and coalesce(new.traslado_nivel, 'mismo_colegio') not in ('mismo_colegio', 'mismo_municipio') then
      raise exception 'Solo la administración de la SNE puede registrar a quien vota en otro municipio';
    end if;

    new.autorizado_por := null;                  -- solo la SNE al aprobar
    new.traslado_resuelto_por := null; new.traslado_resuelto_en := null; new.traslado_nota := null;
    new.colegio_solicitado := null;

    -- ── Colegio de trabajo ──
    if new.colegio_asignado is null and coalesce(new.traslado_nivel, '') = 'mismo_colegio' then
      new.colegio_asignado := new.id_colegio_padron;      -- vota aquí: se asigna solo
    end if;
    if new.traslado_estado = 'pendiente' then
      new.colegio_solicitado := new.colegio_asignado;     -- espera a la SNE, no cuenta
      new.colegio_asignado   := null;
    end if;
  end if;

  -- ── Regla B: el colegio de trabajo pertenece al municipio de registro ──
  if new.colegio_asignado is not null and not exists (
       select 1 from delegados._colegio_full f
        where f.id_colegio = new.colegio_asignado and f.municipio_id = new.municipio_id
       union all
       select 1 from delegados._colegio_oclee co
        where co.id_colegio = new.colegio_asignado and co.municipio_id = new.municipio_id)
  then
    raise exception 'El colegio % no pertenece al municipio de registro', new.colegio_asignado;
  end if;

  if tg_op = 'UPDATE' and new.colegio_asignado is distinct from old.colegio_asignado
     and new.asignado_en is not distinct from old.asignado_en then
    new.asignado_por := coalesce((select u.nombre from usuarios_territoriales u where u.id = auth.uid()), new.asignado_por);
    new.asignado_en  := now();
  end if;

  return new;
end $$;


-- ── 4. Asignar y mover colegio: quién puede ──
create or replace function delegados.portal_reasignar_colegio(p_postulante bigint, p_colegio integer, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_ant integer; v_ced text; v_mun integer; v_ok boolean;
        v_prov integer; v_reg text;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();

  select colegio_asignado, cedula, municipio_id into v_ant, v_ced, v_mun
    from postulantes_2028 where id = p_postulante;
  if v_ced is null then
    return jsonb_build_object('ok', false, 'msg', 'Postulante no encontrado.');
  end if;

  -- Permiso: administración en todo el país; en su municipio, quien tiene permiso de registrar
  select m.provincia_id, m.macroregion into v_prov, v_reg
    from portal_metas_municipio m where m.municipio_id = v_mun;
  if not (portal_rol() = 'admin_sne'
          or (coalesce(portal_puede_registrar(), false) and portal_ve_municipio(v_mun, v_prov, v_reg))) then
    return jsonb_build_object('ok', false,
      'msg', 'No tienes permiso para asignar colegio en este territorio.');
  end if;

  -- El colegio de destino debe pertenecer al territorio del postulante
  select exists (
    select 1 from portal_colegios_territorio(v_mun, null) t where t.id_colegio = p_colegio
  ) into v_ok;
  if not v_ok then
    return jsonb_build_object('ok', false,
      'msg', 'Ese colegio no pertenece al territorio del postulante.');
  end if;

  update postulantes_2028
     set colegio_asignado = p_colegio, asignado_por = v_nom, asignado_en = now()
   where id = p_postulante;

  perform portal_log('reasignacion_colegio', 'postulante', v_ced,
    jsonb_build_object('antes', v_ant, 'despues', p_colegio, 'nota', p_nota));

  return jsonb_build_object('ok', true, 'msg', 'Colegio actualizado.');
end $$;

-- Comprobación (sin sesión). Esperado: 1 fila: excede_accion con valor y encargado_solo_municipio = true.
select alcance, excede_accion, requiere_autorizacion, encargado_solo_municipio from delegados.config_traslados where id;
