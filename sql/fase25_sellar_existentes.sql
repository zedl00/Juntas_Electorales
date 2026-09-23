-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 25
--  SELLADO RETROACTIVO DE LOS EXPEDIENTES YA REGISTRADOS
-- ----------------------------------------------------------------
--  El disparador de la fase 24 sella los expedientes NUEVOS. Los que
--  ya existían quedaron fuera de la cadena, por eso el portal
--  mostraba «0 expedientes sellados».
--
--  Esta función los sella en su orden cronológico real, formando la
--  cadena desde el primer registro. Se ejecuta una sola vez; los
--  posteriores se sellan solos.
--
--  EJECUTAR COMPLETO. Requiere fase24.
-- ================================================================

set search_path = delegados, public;

create or replace function delegados.portal_sellar_existentes()
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public, extensions as $$
declare
  r record; v_prev text; v_base text; v_hash text; v_n integer := 0;
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede sellar la cadena';
  end if;

  -- Se continúa desde el último sello existente, si lo hubiera
  select sello_hash into v_prev from postulantes_2028
   where sello_hash is not null order by sello_at desc nulls last limit 1;

  for r in
    select * from postulantes_2028
     where sello_hash is null
     order by created_at, id
  loop
    v_base := concat_ws('|', r.cedula, r.nombres, r.apellido1, coalesce(r.apellido2,''),
                        r.municipio_id::text, coalesce(r.id_colegio_padron::text,''),
                        r.cargo_postulado, r.numero_formulario,
                        coalesce(v_prev, 'GENESIS'));
    v_hash := encode(extensions.digest(v_base, 'sha256'), 'hex');

    update postulantes_2028
       set sello_hash = v_hash, sello_anterior = v_prev, sello_at = coalesce(created_at, now())
     where id = r.id;

    v_prev := v_hash;
    v_n := v_n + 1;
  end loop;

  perform portal_log('sellado_masivo', 'cadena', null, jsonb_build_object('sellados', v_n));
  return jsonb_build_object('ok', true, 'sellados', v_n);
end $$;

revoke all on function delegados.portal_sellar_existentes() from public, anon;
grant execute on function delegados.portal_sellar_existentes() to authenticated;

notify pgrst, 'reload schema';

-- ── EJECUTAR UNA VEZ ──
--   select delegados.portal_sellar_existentes();
--   select * from delegados.portal_verificar_cadena();
