-- fase63_control_colegio_en_base.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Decisión de la Comisión (23 sep 2026): Opción 1 del documento
-- docs/ASIGNACION_DE_COLEGIOS.md. El alcance configurado manda de verdad y las
-- dos reglas pasan a la base de datos:
--
--   Regla A · Alcance del traslado: la base calcula nivel y estado con la
--             configuración vigente; el cliente ya no decide nada de eso.
--   Regla B · El colegio de trabajo pertenece al municipio de registro.
--
-- Además:
--   · Los datos del padrón se toman de la Junta al insertar, no del cliente.
--   · Un traslado «pendiente» guarda el colegio elegido en colegio_solicitado
--     y deja colegio_asignado vacío: NO cuenta para la cobertura hasta que la
--     SNE lo apruebe (portal_traslado_resolver lo mueve al aprobar).
--   · Un traslado «rechazado» no puede recibir colegio salvo por la administración.
--   · autorizado_por queda vacío hasta que la SNE aprueba.
--   · Quien no es administrador no puede tocar cédula, territorio, datos del
--     padrón, traslado, sellos ni auditoría.
--   · El distrito (jce_id) es el del colegio donde TRABAJARÁ.

alter table delegados.postulantes_2028 add column if not exists colegio_solicitado integer;

-- ── 1. Disparador de control (nombre «aa_» para que corra antes que los demás) ──
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
    if new.id_colegio_padron is not null then
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

drop trigger if exists aa_p28_control_colegio on delegados.postulantes_2028;
create trigger aa_p28_control_colegio
  before insert or update on delegados.postulantes_2028
  for each row execute function delegados.trg_p28_control_colegio();

-- ── 2. Distrito según el colegio donde trabajará ──
create or replace function delegados.trg_p28_geo()
returns trigger language plpgsql security definer set search_path = delegados, public as $$
begin
  select v.provincia_id, v.macroregion into new.provincia_id, new.macroregion
    from portal_metas_municipio v where v.municipio_id = new.municipio_id;

  if new.colegio_asignado is not null then
    select cd.jce_distrito into new.jce_id
      from delegados._colegio_distrito cd where cd.id_colegio = new.colegio_asignado;
  elsif new.id_colegio_padron is not null
        and new.municipio_padron_id is not distinct from new.municipio_id then
    select cd.jce_distrito into new.jce_id
      from delegados._colegio_distrito cd where cd.id_colegio = new.id_colegio_padron;
  else
    new.jce_id := null;                          -- viene de fuera y aún no tiene colegio
  end if;
  return new;
end $$;

-- ── 3. «Esperan colegio» no incluye traslados pendientes ni rechazados ──
create or replace function delegados.portal_sin_colegio(p_municipio integer default null)
returns table(id bigint, numero_formulario text, cedula text, nombre text, cargo text, telefono text,
              municipio_id integer, territorio text, vota_recinto text, vota_colegio text,
              vota_municipio text, created_at timestamp with time zone)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;

  return query
  select p.id, p.numero_formulario::text, p.cedula::text,
         btrim(p.nombres || ' ' || coalesce(p.apellido1,'') || ' ' || coalesce(p.apellido2,''))::text,
         p.cargo_postulado::text, p.telefono::text,
         p.municipio_id::integer,
         coalesce(coalesce(d.nombre || ' · ', '') || m.nombre, m.nombre, '')::text,
         coalesce(p.recinto_padron_desc, p.recinto_nombre, '—')::text,
         coalesce(p.colegio_padron_desc,
                  nullif(btrim(coalesce(p.codigo_colegio,'')), ''), '—')::text,
         coalesce(mp.nombre, '(fuera del padrón)')::text,
         p.created_at
    from postulantes_2028 p
    left join portal_metas_municipio m  on m.municipio_id = p.municipio_id
    left join portal_metas_municipio mp on mp.municipio_id = p.municipio_padron_id
    left join portal_distritos d on d.jce_id = p.jce_id and d.municipio_id = p.municipio_id
   where p.colegio_asignado is null
     and p.estado not in ('rechazado','no_aprobado')
     and coalesce(p.traslado_estado, '') not in ('pendiente', 'rechazado')
     and (p_municipio is null or p.municipio_id = p_municipio)
     and delegados.portal_ve_municipio(p.municipio_id, m.provincia_id, m.macroregion)
   order by m.nombre, p.created_at;
end $$;

-- ── 4. Al aprobar un traslado, el colegio solicitado pasa a asignado ──
create or replace function delegados.portal_traslado_resolver(p_id bigint, p_aprobar boolean, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_ced text; v_form text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede resolver traslados';
  end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();

  update postulantes_2028
     set traslado_estado       = case when p_aprobar then 'aprobado' else 'rechazado' end,
         traslado_resuelto_por = v_nom,
         traslado_resuelto_en  = now(),
         traslado_nota         = p_nota,
         autorizado_por        = case when p_aprobar then v_nom else autorizado_por end,
         colegio_asignado      = case when p_aprobar then coalesce(colegio_solicitado, colegio_asignado) else colegio_asignado end,
         asignado_por          = case when p_aprobar and colegio_solicitado is not null then v_nom else asignado_por end,
         asignado_en           = case when p_aprobar and colegio_solicitado is not null then now() else asignado_en end
   where id = p_id and traslado_estado = 'pendiente'
   returning cedula, numero_formulario into v_ced, v_form;

  if v_ced is null then
    return jsonb_build_object('ok', false, 'msg', 'El traslado ya fue resuelto o no existe.');
  end if;

  perform portal_log(case when p_aprobar then 'traslado_aprobado' else 'traslado_rechazado' end,
                     'postulante', v_ced,
                     jsonb_build_object('formulario', v_form, 'nota', p_nota));

  return jsonb_build_object('ok', true,
    'msg', case when p_aprobar then 'Traslado aprobado: la persona ya cuenta para su colegio.' else 'Traslado rechazado.' end);
end $$;

-- ── Comprobación (sin sesión) ──
-- a) Orden de disparadores: aa_p28_control_colegio debe ser el PRIMERO de la lista.
select tgname from pg_trigger
 where tgrelid = 'delegados.postulantes_2028'::regclass and not tgisinternal
 order by tgname;
-- b) La columna nueva existe.
select column_name from information_schema.columns
 where table_schema = 'delegados' and table_name = 'postulantes_2028' and column_name = 'colegio_solicitado';
