-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 21
--  CORRECCIÓN CRÍTICA: EL POSTULANTE GUARDABA EL DISTRITO EQUIVOCADO
-- ----------------------------------------------------------------
--  PROBLEMA: el trigger de georreferencia tomaba jce_colegio.id_municipio,
--  que apunta a la CABECERA del municipio, no al distrito real del
--  colegio. Consecuencia: un usuario asignado a un distrito no podía
--  registrar (la regla de seguridad exige que el distrito del
--  postulante coincida con el suyo) y los conteos por distrito
--  quedaban en cero.
--
--  El distrito correcto sale de la cadena ya validada:
--    colegio → recinto → sector/paraje → ciudad-sección → distrito
--  (vista delegados._colegio_distrito).
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase20.
-- ================================================================

set search_path = delegados, public;

create or replace function delegados.trg_p28_geo() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  select v.provincia_id, v.macroregion into new.provincia_id, new.macroregion
    from portal_metas_municipio v where v.municipio_id = new.municipio_id;

  if new.id_colegio_padron is not null then
    -- distrito REAL del colegio (cabecera o distrito municipal)
    select cd.jce_distrito into new.jce_id
      from delegados._colegio_distrito cd
     where cd.id_colegio = new.id_colegio_padron;
  end if;
  return new;
end $$;

drop trigger if exists p28_geo on delegados.postulantes_2028;
create trigger p28_geo
before insert or update of municipio_id, id_colegio_padron on delegados.postulantes_2028
for each row execute function delegados.trg_p28_geo();

-- Corregir los registros ya existentes
update delegados.postulantes_2028 p
   set jce_id = cd.jce_distrito
  from delegados._colegio_distrito cd
 where cd.id_colegio = p.id_colegio_padron
   and p.jce_id is distinct from cd.jce_distrito;

notify pgrst, 'reload schema';

-- ================================================================
--  CONSULTAS DE APOYO PARA LAS PRUEBAS
-- ================================================================

-- (A) CÉDULAS REALES PARA REGISTRAR EN UN DISTRITO
--     Devuelve personas del padrón que votan en el distrito indicado.
create or replace function delegados.portal_cedulas_de_prueba(p_jce integer, p_limite integer default 12)
returns table (cedula text, nombre text, colegio text, recinto text)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración de la SNE puede usar esta consulta de apoyo';
  end if;
  return query
  select pa.cedula::text,
         btrim(concat_ws(' ', pa.nombres, pa.apellido1, pa.apellido2))::text,
         coalesce(nullif(btrim(c.codigo_colegio::text),''), c.descripcion::text)::text,
         coalesce(rc.descripcion::text,'—')::text
    from delegados._colegio_distrito cd
    join public.jce_colegio c on c.id_colegio = cd.id_colegio
    left join public.jce_recinto rc on rc.id = c.id_recinto
    join public.jce_padron pa on pa.id_colegio = c.id_colegio and pa.activo
   where cd.jce_distrito = p_jce
   order by rc.descripcion, c.codigo_colegio, pa.cedula
   limit greatest(1, least(coalesce(p_limite, 12), 60));
end $$;

revoke all on function delegados.portal_cedulas_de_prueba(integer, integer) from public, anon;
grant execute on function delegados.portal_cedulas_de_prueba(integer, integer) to authenticated;

-- USO:
--   select * from delegados.portal_cedulas_de_prueba(190, 12);   -- Pedro Corto
--   select * from delegados.portal_cedulas_de_prueba(12, 12);    -- cabecera San Juan

-- (B) LIMPIEZA DE LAS PRUEBAS
--     Elimina solo lo registrado por los usuarios de prueba 0990000xx.
--     La eliminación queda en la bitácora con el expediente completo.
--
--   delete from delegados.postulantes_2028
--    where created_by in (select id from delegados.usuarios_territoriales
--                          where cedula like '0990000%');
--
--     Y para borrar los propios usuarios de prueba:
--   delete from delegados.usuarios_territoriales where cedula like '0990000%';
--   delete from auth.users where email like '0990000%@strategosfp.com';
