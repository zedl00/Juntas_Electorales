-- fase70_colegio_info.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Datos legibles de cualquier colegio por su identificador: código, nombre,
-- recinto, distrito y municipio. La pantalla Asignación lo usa en la vista
-- nacional (donde no hay lista de colegios cargada) para no mostrar nunca el
-- número interno, y sirve para etiquetar colegios en cualquier otra pantalla.

create or replace function delegados.portal_colegio_info(p_ids integer[])
returns table(id_colegio integer, codigo text, colegio text, recinto text, distrito text, municipio_id integer, municipio text)
language sql stable security definer set search_path = delegados, public as $$
  select distinct on (c.id_colegio)
         c.id_colegio::integer,
         coalesce(nullif(btrim(c.codigo_colegio::text), ''), c.id_colegio::text)::text,
         coalesce(nullif(btrim(c.descripcion::text), ''), 'Colegio ' || c.id_colegio)::text,
         coalesce(rc.descripcion::text, '—')::text,
         coalesce(u.nombre, uo.nombre, '')::text,
         coalesce(u.municipio_id, co.municipio_id)::integer,
         coalesce(m.nombre, '')::text
    from public.jce_colegio c
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join delegados._colegio_distrito cd on cd.id_colegio = c.id_colegio
    left join delegados._unidades_jce u on u.jce_id = cd.jce_distrito
    left join delegados._colegio_oclee co on co.id_colegio = c.id_colegio
    left join delegados._unidades_oclee uo on uo.oclee_id = co.oclee_id and uo.municipio_id = co.municipio_id
    left join delegados.portal_metas_municipio m on m.municipio_id = coalesce(u.municipio_id, co.municipio_id)
   where c.id_colegio = any(p_ids)
     and delegados.portal_rol() is not null
   order by c.id_colegio;
$$;
revoke execute on function delegados.portal_colegio_info(integer[]) from public, anon;
grant  execute on function delegados.portal_colegio_info(integer[]) to authenticated;

-- Comprobación (sin sesión): la función existe. Esperado: 1 fila.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.proname = 'portal_colegio_info';
