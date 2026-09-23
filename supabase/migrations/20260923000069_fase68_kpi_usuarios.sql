-- fase68_kpi_usuarios.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Avance por territorio para la lista de usuarios (Gestión → Usuarios):
-- una fila por municipio (jce_id nulo) y una por distrito, con colegios,
-- meta (colegios × 3) y registrados. La pantalla cruza cada usuario con la
-- fila de su municipio o distrito; para supervisores provinciales y
-- coordinadores regionales suma los municipios de su alcance.

create or replace function delegados.portal_kpi_usuarios()
returns table(municipio_id integer, jce_id integer, colegios bigint, meta bigint, total bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() not in ('admin_sne','consulta_nacional') then
    raise exception 'Solo la administración de la SNE puede ver el avance por usuario';
  end if;
  return query
  select m.municipio_id::integer, null::integer,
         coalesce(m.colegios, 0)::bigint, coalesce(m.meta, 0)::bigint,
         (select count(*) from postulantes_2028 p
           where p.municipio_id = m.municipio_id
             and p.estado not in ('rechazado','no_aprobado'))::bigint
    from portal_metas_municipio m
  union all
  select d.municipio_id::integer, d.jce_id::integer,
         coalesce(d.colegios, 0)::bigint, coalesce(d.meta, 0)::bigint,
         (select count(*) from postulantes_2028 p
           where p.municipio_id = d.municipio_id and p.jce_id = d.jce_id
             and p.estado not in ('rechazado','no_aprobado'))::bigint
    from portal_distritos d;
end $$;
revoke execute on function delegados.portal_kpi_usuarios() from public, anon;
grant  execute on function delegados.portal_kpi_usuarios() to authenticated;

-- Comprobación (sin sesión): la función existe. Esperado: 1 fila.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.proname = 'portal_kpi_usuarios';
