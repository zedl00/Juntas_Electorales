-- fase71_bandeja_traslados_colegio_solicitado.sql · Portal de Delegados 2028
-- Idempotente.
--
-- La bandeja Dirigencia → Traslados mostraba en «Trabajaría en» el colegio del
-- padrón (codigo_colegio) en vez del colegio solicitado o asignado, y
-- «Registrado por» leía autorizado_por, que desde la fase 63 queda vacío hasta
-- la aprobación. Ahora:
--   trabaja_colegio  = código y recinto del colegio solicitado (pendiente) o asignado
--   registrado_por   = nombre del usuario que registró (registrado_por → usuarios_territoriales)

create or replace function delegados.portal_traslados_pendientes(p_estado text default 'pendiente')
returns table(id bigint, numero_formulario text, cedula text, nombre text, cargo text, telefono text,
              vota_territorio text, vota_colegio text, trabaja_territorio text, trabaja_colegio text,
              nivel text, estado text, registrado_por text, created_at timestamp with time zone,
              resuelto_por text, resuelto_en timestamp with time zone)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if portal_rol() not in ('admin_sne','consulta_nacional') then
    raise exception 'Solo la administración de la SNE puede ver los traslados';
  end if;
  return query
  select p.id, p.numero_formulario::text, p.cedula::text,
         btrim(p.nombres || ' ' || coalesce(p.apellido1,'') || ' ' || coalesce(p.apellido2,''))::text,
         p.cargo_postulado::text, p.telefono::text,
         coalesce(mp.nombre || ' · ' || coalesce(mp.provincia_nombre,''), '(no localizado)')::text,
         coalesce(p.colegio_padron_desc,'')::text,
         coalesce(coalesce(d.nombre || ' · ', '') || mt.nombre || ' · ' || coalesce(mt.provincia_nombre,''), '')::text,
         case when ct.id_colegio is null then ''
              else coalesce(nullif(btrim(ct.codigo_colegio::text),''), ct.id_colegio::text)
                   || coalesce(' — ' || rt.descripcion, '') end::text,
         p.traslado_nivel::text, p.traslado_estado::text,
         coalesce(ur.nombre, '')::text, p.created_at,
         p.traslado_resuelto_por::text, p.traslado_resuelto_en
    from postulantes_2028 p
    left join portal_metas_municipio mt on mt.municipio_id = p.municipio_id
    left join portal_metas_municipio mp on mp.municipio_id = p.municipio_padron_id
    left join portal_distritos d on d.jce_id = p.jce_id and d.municipio_id = p.municipio_id
    left join public.jce_colegio ct on ct.id_colegio = coalesce(p.colegio_solicitado, p.colegio_asignado)
    left join public.jce_recinto rt on rt.id = ct.id_recinto
    left join usuarios_territoriales ur on ur.id = p.registrado_por
   where p.estado not in ('rechazado','no_aprobado')
     and (p_estado is null or p_estado = 'todos' or p.traslado_estado = p_estado)
     and p.traslado_estado <> 'no_aplica'
   order by case p.traslado_estado when 'pendiente' then 0 else 1 end, p.created_at desc;
end $$;

-- Comprobación (sin sesión): la función usa colegio_solicitado. Esperado: 1 fila con ok = true.
select p.proname, pg_get_functiondef(p.oid) like '%colegio_solicitado%' as ok
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados' and p.prokind = 'f' and p.proname = 'portal_traslados_pendientes';
