-- fase61_cobertura_colegio_asignado.sql · Portal de Delegados 2028
-- Idempotente (create or replace).
--
-- 1. Corrige el error 42702 «column reference "municipio_id" is ambiguous» en
--    portal_cobertura_resumen: la rama OCLEE seleccionaba municipio_id sin
--    prefijo y chocaba con la columna de salida del mismo nombre.
-- 2. Alinea el conteo de cobertura de Inicio con la regla de la v8.6: la
--    persona cuenta para el colegio donde TRABAJARÁ (colegio_asignado), no para
--    el colegio donde vota (id_colegio_padron). Igual que ya hacen
--    portal_colegios_territorio y portal_cobertura_colegios.
--
-- Pendiente (fase 62): aplicar la misma regla en portal_kpi_distritos,
-- portal_kpi_filtro, portal_bot_nivel y portal_bot_resumen.

create or replace function delegados.portal_cobertura_resumen()
returns table (municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_dist smallint := portal_distrito();
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  return query
  with alcance as (
    select m.municipio_id from portal_metas_municipio m
     where (m.estatus is null or m.estatus <> 'I')
       and delegados.portal_ve_municipio(m.municipio_id, m.provincia_id, m.macroregion)),
  todos as (
    select u.municipio_id, cd.id_colegio
      from delegados._unidades_jce u
      join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
     where (v_dist is null or u.jce_id = v_dist)
    union all
    select co.municipio_id, co.id_colegio from delegados._colegio_oclee co),
  cole as (
    select a.municipio_id mun_id, t.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) personas
      from alcance a join todos t on t.municipio_id = a.municipio_id
      /* Se cuenta por el colegio ASIGNADO, sin exigir el municipio del padrón */
      left join postulantes_2028 p on p.colegio_asignado = t.id_colegio
     group by a.municipio_id, t.id_colegio)
  select cole.mun_id, count(*)::bigint,
         count(*) filter (where personas >= 3), count(*) filter (where personas > 0 and personas < 3),
         count(*) filter (where personas = 0)
    from cole group by cole.mun_id;
end $$;

create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_dist smallint := portal_distrito(); v jsonb;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;

  with alcance as (
    select v2.municipio_id, v2.meta, v2.colegios
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (p_municipio is null or v2.municipio_id = p_municipio)
       and delegados.portal_ve_municipio(v2.municipio_id, v2.provincia_id, v2.macroregion)
  ),
  post as (
    select p.* from postulantes_2028 p
      join alcance a on a.municipio_id = p.municipio_id
     where (v_dist is null or p.jce_id = v_dist)
  ),
  tot as (
    select case when v_dist is null then (select coalesce(sum(meta),0) from alcance)
                else (select coalesce(sum(d.meta),0) from portal_distritos d where d.jce_id = v_dist) end as meta,
           case when v_dist is null then (select coalesce(sum(colegios),0) from alcance)
                else (select coalesce(sum(d.colegios),0) from portal_distritos d where d.jce_id = v_dist) end as col
  ),
  /* Colegio cubierto = 3 o más personas ASIGNADAS a ese colegio */
  cub as (select count(*) n from (
      select colegio_asignado from post
       where estado not in ('rechazado','no_aprobado') and colegio_asignado is not null
       group by colegio_asignado having count(*) >= 3) x)
  select jsonb_build_object(
    'meta', (select meta from tot), 'colegios', (select col from tot),
    'colegios_cubiertos', (select n from cub),
    'total',   (select count(*) from post where estado not in ('rechazado','no_aprobado')),
    'hoy',     (select count(*) from post where created_at::date = current_date),
    'semana',  (select count(*) from post where created_at >= now() - interval '7 days'),
    'con_experiencia', (select count(*) from post where experiencia_2024 or experiencia_2020),
    'exp_2020',(select count(*) from post where experiencia_2020),
    'exp_2024',(select count(*) from post where experiencia_2024),
    'firmes',  (select count(*) from post where candidato_firme),
    'por_estado', (select jsonb_object_agg(estado, n) from (select estado, count(*) n from post group by estado) e),
    'por_cargo',  (select jsonb_object_agg(cargo_postulado, n) from (select cargo_postulado, count(*) n from post group by cargo_postulado) c)
  ) into v;
  return v;
end $$;

-- Comprobación: debe devolver filas (una por municipio visible) sin error.
select count(*) as municipios_con_cobertura from delegados.portal_cobertura_resumen();
