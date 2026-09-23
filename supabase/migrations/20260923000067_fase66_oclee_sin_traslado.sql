-- fase66_oclee_sin_traslado.sql · Portal de Delegados 2028
-- Idempotente (create or replace del mismo disparador de las fases 63 y 64).
--
-- En las oficinas del exterior (OCLEE) no aplica la verificación de demarcación:
-- la pantalla ya lo decía, pero el disparador de la fase 63 calculaba igual el
-- traslado y, con la fase 64, habría bloqueado al encargado de una OCLEE al
-- registrar a alguien cuyo colegio del padrón está en el país. Con esta fase,
-- un registro bajo una OCLEE queda siempre con traslado «no_aplica».
--
-- Cambio respecto a la fase 64: la condición del bloque «Traslado» excluye los
-- municipios de tipo OCLEE. Todo lo demás es idéntico.

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
    -- ── Límite del encargado: solo registra a quien vota en su propio municipio (fase 64) ──
    if not (v_admin or v_sin_sesion)
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

-- Comprobación (sin sesión): el disparador debe contener la exclusión de OCLEE. Esperado: 1 fila con ok = true.
select p.proname, pg_get_functiondef(p.oid) like '%OCLEE%' as ok
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.prokind = 'f' and p.proname = 'trg_p28_control_colegio';
