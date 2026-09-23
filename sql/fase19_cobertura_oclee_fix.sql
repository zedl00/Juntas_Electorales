-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 19
--  CORRECCIÓN: «column u.circ_id does not exist» al abrir una OCLEE
-- ----------------------------------------------------------------
--  La vista delegados._unidades_oclee expone circ_codigo y circ_nombre
--  desde la fase 15, pero portal_cobertura_colegios seguía pidiendo
--  la columna circ_id que existía en la fase 14. Se reescribe la
--  función completa con los nombres vigentes.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase18.
-- ================================================================

set search_path = delegados, public;

drop function if exists delegados.portal_cobertura_colegios(integer, integer, integer);
create function delegados.portal_cobertura_colegios(
  p_municipio integer, p_jce integer default null, p_circ integer default null)
returns table (
  distrito text, jce_id integer, circunscripcion text, circ_id integer,
  id_colegio integer, colegio text, recinto text, recinto_dir text,
  inscritos bigint, titulares bigint, suplentes bigint, observadores bigint,
  indistintos bigint, personas bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text; v_tipo text;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;
  select v2.provincia_id, v2.macroregion, v2.tipo into v_prov, v_reg, v_tipo
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not (
    v_rol = 'admin_sne'
    or (v_rol in ('presidente','secretario_general','enc_electoral') and p_municipio = portal_mun())
    or (v_rol = 'supervisor_provincial' and v_prov = portal_prov())
    or (v_rol = 'coordinador_regional'  and v_reg = portal_region())
  ) then
    raise exception 'Territorio fuera de tu alcance';
  end if;
  if v_dist is not null then p_jce := v_dist::integer; end if;

  if coalesce(v_tipo,'') = 'OCLEE' then
    -- ── Exterior: la oficina es la unidad; su circunscripción es de texto ──
    return query
    select u.nombre::text,
           u.jce_id::integer,
           u.circ_nombre::text,
           null::integer,
           c.id_colegio::integer,
           coalesce(nullif(btrim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
           coalesce(rc.descripcion::text,'—')::text,
           coalesce(rc.direccion::text,'')::text,
           coalesce(max(c.cantidad_inscritos),0)::bigint,
           count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
      from delegados._unidades_oclee u
      join delegados._colegio_oclee co on co.oclee_id = u.oclee_id and co.municipio_id = u.municipio_id
      join public.jce_colegio c on c.id_colegio = co.id_colegio
      left join public.jce_recinto rc on rc.id = c.id_recinto
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
     group by u.nombre, u.jce_id, u.circ_nombre,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by 7, 6;
  else
    -- ── Nacional: distrito y circunscripción desde la cadena JCE ──
    return query
    select u.nombre::text,
           u.jce_id::integer,
           coalesce(nullif(btrim(ci.descripcion),''), 'Circ. ' || ci.codigo_circunscripcion, '—')::text,
           ci.id::integer,
           c.id_colegio::integer,
           coalesce(nullif(btrim(c.codigo_colegio::text),''), c.descripcion::text, 'Colegio '||c.id_colegio)::text,
           coalesce(rc.descripcion::text,'—')::text,
           coalesce(rc.direccion::text,'')::text,
           coalesce(max(c.cantidad_inscritos),0)::bigint,
           count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
      from delegados._unidades_jce u
      join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
      join public.jce_colegio c on c.id_colegio = cd.id_colegio
      left join public.jce_recinto rc on rc.id = c.id_recinto
      left join public.jce_circunscripcion ci on ci.id = cd.circ_id
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio and p.municipio_id = p_municipio
     where u.municipio_id = p_municipio
       and (p_jce  is null or u.jce_id = p_jce)
       and (p_circ is null or cd.circ_id = p_circ)
     group by u.nombre, u.jce_id, u.es_dm, ci.id, ci.descripcion, ci.codigo_circunscripcion,
              c.id_colegio, c.codigo_colegio, c.descripcion, rc.descripcion, rc.direccion
     order by u.es_dm, u.nombre, coalesce(rc.descripcion,''), 6;
  end if;
end $$;

revoke all on function delegados.portal_cobertura_colegios(integer, integer, integer) from public, anon;
grant execute on function delegados.portal_cobertura_colegios(integer, integer, integer) to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  Una OCLEE (debe responder sin error, aunque devuelva 0 filas si no
--  tiene colegios cargados):
--   select * from delegados.portal_cobertura_colegios(
--     (select id from public.municipios where nombre = 'California'));
--  Un municipio nacional:
--   select distrito, circunscripcion, colegio from delegados.portal_cobertura_colegios(
--     (select id from public.municipios where nombre ilike '%san juan de la maguana%')) limit 5;
