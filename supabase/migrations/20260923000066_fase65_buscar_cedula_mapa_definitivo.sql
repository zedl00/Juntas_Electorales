-- fase65_buscar_cedula_mapa_definitivo.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Diagnóstico del 23 sep 2026 con la cédula 00100676527 (Distrito Nacional):
--   _mapeo_municipio (tabla vieja)  → Tamboril            ← MAL
--   _par_municipio / _unidades_jce  → Santo Domingo de Guzmán  ← correcto
--   portal_colegio_detalle          → Santo Domingo de Guzmán  ← correcto
--
-- portal_buscar_cedula era la única función viva que seguía usando la tabla
-- vieja para decir «vota en …». Por eso la pantalla mostraba Tamboril y el
-- registro creía que la persona votaba fuera. Pasa a usar _unidades_jce, la
-- misma correspondencia que usan la cobertura y el traslado.
--
-- También se eliminan dos versiones antiguas de funciones del asistente que
-- usaban la tabla vieja y que nadie llama (los bots pasan siempre p_cedula).

create or replace function delegados.portal_buscar_cedula(p_ced text)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare
  v_ced text := regexp_replace(coalesce(p_ced,''), '\D', '', 'g');
  v_fmt text;
  r record;
  v_mun_app integer;
  v_mun_app_nombre text;
  v_exp integer := 0;
  v_post record;
  v_es_usuario boolean := false;
begin
  if portal_rol() is null then
    raise exception 'Acceso no autorizado';
  end if;
  if length(v_ced) < 8 then
    return jsonb_build_object('encontrado', false, 'error', 'Cédula incompleta');
  end if;

  select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
         pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
         pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
         pa.id_municipio,
         c.descripcion  as colegio_desc,
         rc.descripcion as recinto_desc,
         rc.direccion   as recinto_dir,
         jm.descripcion as jce_municipio
    into r
    from jce_padron pa
    left join jce_colegio  c  on c.id_colegio = pa.id_colegio
    left join jce_recinto  rc on rc.id = c.id_recinto
    left join jce_municipio jm on jm.id = pa.id_municipio
   where pa.cedula = v_ced and pa.activo
   limit 1;

  if not found and length(v_ced) = 11 then
    v_fmt := substr(v_ced,1,3) || '-' || substr(v_ced,4,7) || '-' || substr(v_ced,11,1);
    select pa.cedula, pa.nombres, pa.apellido1, pa.apellido2, pa.id_sexo,
           pa.fecha_nacimiento, pa.lugar_votacion, pa.id_colegio,
           pa.codigo_colegio, pa.codigo_recinto, pa.codigo_circunscripcion,
           pa.id_municipio,
           c.descripcion  as colegio_desc,
           rc.descripcion as recinto_desc,
           rc.direccion   as recinto_dir,
           jm.descripcion as jce_municipio
      into r
      from jce_padron pa
      left join jce_colegio  c  on c.id_colegio = pa.id_colegio
      left join jce_recinto  rc on rc.id = c.id_recinto
      left join jce_municipio jm on jm.id = pa.id_municipio
     where pa.cedula = v_fmt and pa.activo
     limit 1;
  end if;

  perform portal_log('consulta_padron', 'cedula', v_ced,
                     jsonb_build_object('encontrado', found));

  if not found then
    return jsonb_build_object('encontrado', false);
  end if;

  /* Municipio del portal donde vota: correspondencia definitiva (la misma de cobertura y traslado) */
  select u.municipio_id into v_mun_app
    from delegados._unidades_jce u where u.jce_id = r.id_municipio limit 1;
  if v_mun_app is not null then
    select nombre into v_mun_app_nombre from municipios where id = v_mun_app;
  end if;

  begin
    select count(*) into v_exp
      from historial_delegado h
     where regexp_replace(coalesce(h.cedula,''), '\D', '', 'g') = v_ced;
  exception when undefined_table or undefined_column then
    v_exp := 0;
  end;

  select numero_formulario, estado, municipio_id into v_post
    from postulantes_2028
   where cedula = v_ced limit 1;

  select exists(
    select 1 from usuarios_territoriales
     where regexp_replace(cedula, '\D', '', 'g') = v_ced
  ) into v_es_usuario;

  return jsonb_build_object(
    'encontrado', true,
    'cedula', v_ced,
    'nombres', r.nombres,
    'apellido1', r.apellido1,
    'apellido2', r.apellido2,
    'sexo', r.id_sexo,
    'fecha_nacimiento', r.fecha_nacimiento,
    'lugar_votacion', r.lugar_votacion,
    'id_colegio', r.id_colegio,
    'codigo_colegio', r.codigo_colegio,
    'colegio_desc', r.colegio_desc,
    'codigo_recinto', r.codigo_recinto,
    'recinto', r.recinto_desc,
    'recinto_dir', r.recinto_dir,
    'circunscripcion', r.codigo_circunscripcion,
    'jce_municipio', r.jce_municipio,
    'municipio_app_id', v_mun_app,
    'municipio_app', v_mun_app_nombre,
    'experiencia_2024', v_exp > 0,
    'experiencia_veces', v_exp,
    'ya_postulado', v_post.numero_formulario is not null,
    'postulado_numero', v_post.numero_formulario,
    'postulado_estado', v_post.estado,
    'postulado_municipio_id', v_post.municipio_id,
    'es_usuario', v_es_usuario
  );
end $$;

-- Versiones antiguas del asistente que usaban la tabla vieja y nadie llama
drop function if exists delegados.portal_bot_nivel(text, text);
drop function if exists delegados.portal_bot_resumen();

-- Comprobación (sin sesión): ninguna función de delegados debe seguir usando _mapeo_municipio.
-- Esperado: cero filas.
select p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and pg_get_functiondef(p.oid) like '%_mapeo_municipio%';
