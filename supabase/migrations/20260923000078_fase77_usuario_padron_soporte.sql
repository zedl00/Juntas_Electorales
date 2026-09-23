-- fase77_usuario_padron_soporte.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Datos del padrón de un usuario del portal, para que la administración dé
-- soporte en la verificación de identidad (fecha de nacimiento y municipio
-- donde vota). Solo administración; cada consulta queda en la bitácora.

create or replace function delegados.portal_usuario_padron(p_cedula text)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g'); pa record; v_mun text;
begin
  if delegados.portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede consultar estos datos';
  end if;
  if not exists (select 1 from usuarios_territoriales u where u.cedula = v_ced) then
    return jsonb_build_object('encontrado', false, 'error', 'No es usuario del portal');
  end if;
  select pa2.fecha_nacimiento, pa2.id_municipio, pa2.lugar_votacion, pa2.codigo_colegio into pa
    from public.jce_padron pa2 where pa2.cedula = v_ced and pa2.activo limit 1;
  if pa.fecha_nacimiento is null and pa.id_municipio is null then
    return jsonb_build_object('encontrado', false);
  end if;
  select m.nombre into v_mun
    from delegados._unidades_jce x join public.municipios m on m.id = x.municipio_id
   where x.jce_id = pa.id_municipio limit 1;
  return jsonb_build_object(
    'encontrado', true,
    'fecha_nacimiento', pa.fecha_nacimiento,
    'municipio', v_mun,
    'colegio', pa.codigo_colegio,
    'exterior', pa.lugar_votacion = 'E');
end $$;
revoke execute on function delegados.portal_usuario_padron(text) from public, anon;
grant  execute on function delegados.portal_usuario_padron(text) to authenticated;

-- La consulta queda en la bitácora (función stable no puede insertar: se registra desde una envoltura)
create or replace function delegados.portal_usuario_padron_log(p_cedula text)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v jsonb;
begin
  v := delegados.portal_usuario_padron(p_cedula);
  perform portal_log('consulta_padron_soporte', 'usuario', regexp_replace(coalesce(p_cedula,''), '\D', '', 'g'),
                     jsonb_build_object('encontrado', v->>'encontrado'));
  return v;
end $$;
revoke execute on function delegados.portal_usuario_padron_log(text) from public, anon;
grant  execute on function delegados.portal_usuario_padron_log(text) to authenticated;

-- Comprobación (sin sesión). Esperado: 2 filas.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.proname in ('portal_usuario_padron','portal_usuario_padron_log') order by 1;
