-- fase72_traslado_reabrir.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Un traslado rechazado deja a la persona registrada pero sin colegio: no
-- cuenta, no aparece en «Esperan colegio», y nadie salvo la administración
-- puede darle colegio en ese territorio. Para que no quede en un callejón sin
-- salida, la administración puede REABRIRLO: vuelve a «pendiente» y entra de
-- nuevo en la bandeja de Dirigencia → Traslados para decidir otra vez.

create or replace function delegados.portal_traslado_reabrir(p_id bigint, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text; v_ced text; v_form text;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede reabrir traslados';
  end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();

  update postulantes_2028
     set traslado_estado       = 'pendiente',
         traslado_resuelto_por = null,
         traslado_resuelto_en  = null,
         traslado_nota         = coalesce(p_nota, traslado_nota),
         autorizado_por        = null
   where id = p_id and traslado_estado = 'rechazado'
   returning cedula, numero_formulario into v_ced, v_form;

  if v_ced is null then
    return jsonb_build_object('ok', false, 'msg', 'Ese traslado no está rechazado o no existe.');
  end if;

  perform portal_log('traslado_reabierto', 'postulante', v_ced,
                     jsonb_build_object('formulario', v_form, 'nota', p_nota, 'por', v_nom));
  return jsonb_build_object('ok', true, 'msg', 'Traslado reabierto: vuelve a la bandeja de la SNE.');
end $$;
revoke execute on function delegados.portal_traslado_reabrir(bigint, text) from public, anon;
grant  execute on function delegados.portal_traslado_reabrir(bigint, text) to authenticated;

-- Comprobación (sin sesión): la función existe. Esperado: 1 fila.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.proname = 'portal_traslado_reabrir';
