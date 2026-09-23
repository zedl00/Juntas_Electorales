-- fase69_formularios_habilitados.sql · Portal de Delegados 2028
-- Idempotente.
--
-- La Comisión puede habilitar o deshabilitar la impresión del formulario en
-- blanco y del formulario individual (lleno). Se guarda en config_documentos,
-- se cambia desde Gestión → Configuración → Marca de agua y documentos, y se
-- aplica en la base (portal_log_impresion), no solo escondiendo botones.

alter table delegados.config_documentos add column if not exists permitir_blanco     boolean not null default true;
alter table delegados.config_documentos add column if not exists permitir_individual boolean not null default true;

create or replace function delegados.portal_config_documentos_set(p_campo text, p_valor boolean)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede cambiar esta configuración';
  end if;
  if p_campo not in ('sello_individual','sello_blanco','sello_relacion',
                     'sello_validacion','sello_resumen',
                     'permitir_blanco','permitir_individual') then
    raise exception 'Campo no válido: %', p_campo;
  end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();

  execute format('update delegados.config_documentos set %I = $1, actualizado = now(), actualizado_por = $2 where id',
                 p_campo) using p_valor, v_nom;

  perform portal_log('config_documentos', 'configuracion', null,
    jsonb_build_object('campo', p_campo, 'valor', p_valor));

  return jsonb_build_object('ok', true, 'campo', p_campo, 'valor', p_valor);
end $$;

create or replace function delegados.portal_log_impresion(p_tipo text, p_territorio text default null, p_registros integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_rol text; v_perm jsonb; v_clave text; v_ok boolean;
        v_campo text; v_sella boolean; v_hab boolean;
begin
  select u.nombre, u.rol into v_nom, v_rol
    from usuarios_territoriales u where u.id = auth.uid();
  if v_nom is null then
    return jsonb_build_object('ok', false, 'msg', 'Sesión no válida.');
  end if;

  if coalesce((select u.puede_imprimir from usuarios_territoriales u where u.id = auth.uid()), true) = false then
    perform portal_log('impresion_denegada', 'documento', null,
                       jsonb_build_object('tipo', p_tipo, 'motivo', 'sin permiso de impresión'));
    return jsonb_build_object('ok', false, 'msg', 'Tu acceso no tiene autorización para imprimir.');
  end if;

  -- ¿La Comisión tiene habilitado este formulario? (fase 69)
  if p_tipo ilike '%blanco%' then
    select permitir_blanco into v_hab from config_documentos where id;
  elsif p_tipo ilike '%individual%' then
    select permitir_individual into v_hab from config_documentos where id;
  end if;
  if coalesce(v_hab, true) = false then
    perform portal_log('impresion_denegada', 'documento', null,
      jsonb_build_object('tipo', p_tipo, 'motivo', 'formulario deshabilitado por la Comisión'));
    return jsonb_build_object('ok', false,
      'msg', case when p_tipo ilike '%blanco%'
                  then 'La Comisión tiene deshabilitado el formulario en blanco.'
                  else 'La Comisión tiene deshabilitada la impresión del formulario individual.' end);
  end if;

  -- Permiso según el tipo de documento
  v_perm := portal_mis_permisos();
  v_clave := case
    when p_tipo ilike '%individual%' or p_tipo ilike '%blanco%' then 'imprimir_individual'
    when p_tipo ilike '%relaci%'                                then 'imprimir_relacion'
    else 'imprimir_validacion' end;
  v_ok := coalesce((v_perm->>v_clave)::boolean, false);

  if not v_ok then
    perform portal_log('impresion_denegada', 'documento', null,
      jsonb_build_object('tipo', p_tipo, 'rol', v_rol, 'permiso', v_clave));
    return jsonb_build_object('ok', false,
      'msg', 'Tu rol no está autorizado a imprimir este documento. Solicítalo a la Comisión.');
  end if;

  -- ¿Este documento lleva marca de agua?
  v_campo := case
    when p_tipo ilike '%blanco%'     then 'sello_blanco'
    when p_tipo ilike '%individual%' then 'sello_individual'
    when p_tipo ilike '%relaci%'     then 'sello_relacion'
    when p_tipo ilike '%general%'    then 'sello_resumen'
    else 'sello_validacion' end;

  execute format('select %I from delegados.config_documentos where id', v_campo) into v_sella;
  v_sella := coalesce(v_sella, true);

  -- La emisión SIEMPRE queda registrada, lleve marca o no
  perform portal_log('impresion', 'documento', null,
    jsonb_build_object('tipo', p_tipo, 'territorio', p_territorio,
                       'registros', p_registros, 'con_marca', v_sella));

  return jsonb_build_object('ok', true, 'nombre', v_nom, 'momento', now(), 'sella', v_sella);
end $$;

-- Comprobación (sin sesión). Esperado: 1 fila con permitir_blanco = true y permitir_individual = true.
select permitir_blanco, permitir_individual from delegados.config_documentos where id;
