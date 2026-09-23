-- fase62_kpi_por_colegio_asignado.sql · Portal de Delegados 2028
-- Idempotente (create or replace).
--
-- Completa lo iniciado en la fase 61: TODAS las funciones que miden cobertura
-- cuentan a la persona en el colegio donde TRABAJARÁ (colegio_asignado), no en
-- el colegio donde vota (id_colegio_padron). Se dejan de exigir coincidencias
-- de municipio en el join, igual que en portal_cobertura_colegios.
--
-- Funciones tocadas: portal_kpi_filtro (tarjeta «Cobertura de colegios» de
-- Inicio), portal_kpi_distritos (tabla por distrito), portal_bot_nivel y
-- portal_bot_resumen (asistente de Telegram/WhatsApp, versiones con cédula).
-- Los cuerpos son los que viven en la base al 23 sep 2026 con solo ese cambio.

-- ── 1. portal_kpi_filtro ──
create or replace function delegados.portal_kpi_filtro(
  p_ambito text default null, p_region text default null, p_provincia integer default null,
  p_municipio integer default null, p_jce integer default null, p_circ integer default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_dist smallint := portal_distrito(); v jsonb;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  if v_dist is not null then p_jce := v_dist::integer; end if;

  with alcance as (
    select m.municipio_id, m.meta from portal_metas_municipio m
     where (m.estatus is null or m.estatus <> 'I')
       and delegados.portal_ve_municipio(m.municipio_id, m.provincia_id, m.macroregion)
       and (p_ambito is null or p_ambito = 'todos'
         or (p_ambito = 'oclee'    and coalesce(m.tipo,'') = 'OCLEE')
         or (p_ambito = 'nacional' and coalesce(m.tipo,'') <> 'OCLEE'))
       and (p_region    is null or m.macroregion  = p_region)
       and (p_provincia is null or m.provincia_id = p_provincia)
       and (p_municipio is null or m.municipio_id = p_municipio)
  ),
  base as (
    select f.* from delegados._colegio_full f join alcance a on a.municipio_id = f.municipio_id
     where (p_jce is null or f.jce_id = p_jce) and (p_circ is null or f.circ_id = p_circ)
  ),
  cole as (
    select b.id_colegio, b.municipio_id,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as n
      from base b
      left join postulantes_2028 p on p.colegio_asignado = b.id_colegio
     group by b.id_colegio, b.municipio_id)
  select jsonb_build_object(
    'municipios', (select count(*) from alcance),
    'pendientes', (select count(*) from alcance where coalesce(meta,0) = 0),
    'recintos',   (select count(distinct id_recinto) from base),
    'colegios',   (select count(distinct id_colegio) from base),
    'electores',  (select coalesce(sum(inscritos),0) from (select distinct id_colegio, inscritos from base) x),
    'meta',       (select count(distinct id_colegio) * 3 from base),
    'registrados',(select coalesce(sum(n),0) from cole),
    'completos',  (select count(*) from cole where n >= 3),
    'parciales',  (select count(*) from cole where n > 0 and n < 3),
    'vacios',     (select count(*) from cole where n = 0)
  ) into v;
  return v;
end $$;

-- ── 2. portal_kpi_distritos ──
create or replace function delegados.portal_kpi_distritos(p_municipio integer)
returns table(jce_id integer, distrito text, es_dm boolean, colegios bigint, meta bigint,
              total bigint, completos bigint, parciales bigint, vacios bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_dist smallint := portal_distrito();
  v_prov integer; v_reg text;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;
  select v2.provincia_id, v2.macroregion into v_prov, v_reg
    from portal_metas_municipio v2 where v2.municipio_id = p_municipio;
  if not (
    v_rol = 'admin_sne'
    or (v_rol in ('presidente','secretario_general','enc_electoral') and p_municipio = portal_mun())
    or (v_rol = 'supervisor_provincial' and v_prov = portal_prov())
    or (v_rol = 'coordinador_regional'  and v_reg = portal_region())
  ) then
    raise exception 'Territorio fuera de tu alcance';
  end if;

  return query
  with cole as (
    select u.jce_id as jce, u.nombre, u.es_dm, cd.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as n
      from delegados._unidades_jce u
      left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
      left join postulantes_2028 p on p.colegio_asignado = cd.id_colegio
     where u.municipio_id = p_municipio
       and (v_dist is null or u.jce_id = v_dist)
     group by u.jce_id, u.nombre, u.es_dm, cd.id_colegio
  )
  select cole.jce, cole.nombre, cole.es_dm,
         count(cole.id_colegio)::bigint,
         (count(cole.id_colegio) * 3)::bigint,
         coalesce(sum(cole.n), 0)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n >= 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n > 0 and cole.n < 3)::bigint,
         count(*) filter (where cole.id_colegio is not null and cole.n = 0)::bigint
    from cole
   group by cole.jce, cole.nombre, cole.es_dm
   order by cole.es_dm, cole.nombre;
end $$;

-- ── 3. portal_bot_nivel (versión con cédula) ──
create or replace function delegados.portal_bot_nivel(p_nivel text, p_clave text, p_cedula text default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare a jsonb; v_ok boolean := false; v jsonb; v_nivel text;
begin
  a := portal_bot_alcance(p_cedula);
  v_nivel := a->>'nivel';

  -- ¿El territorio pedido cae dentro del alcance?
  if v_nivel = 'nacional' then
    v_ok := true;
  elsif v_nivel = 'region' then
    v_ok := (p_nivel = 'region'    and delegados._norm(p_clave) = delegados._norm(a->>'region'))
         or (p_nivel in ('provincia','municipio') and exists (
              select 1 from portal_metas_municipio m
               where m.macroregion = (a->>'region')
                 and ((p_nivel = 'provincia' and delegados._norm(m.provincia_nombre) = delegados._norm(p_clave))
                   or (p_nivel = 'municipio' and delegados._norm(m.nombre) = delegados._norm(p_clave)))));
  elsif v_nivel = 'provincia' then
    v_ok := exists (select 1 from portal_metas_municipio m
                     where m.provincia_id = (a->>'provincia_id')::integer
                       and ((p_nivel = 'provincia' and delegados._norm(m.provincia_nombre) = delegados._norm(p_clave))
                         or (p_nivel = 'municipio' and delegados._norm(m.nombre) = delegados._norm(p_clave))));
  else
    v_ok := (p_nivel = 'municipio' and exists (
              select 1 from portal_metas_municipio m
               where m.municipio_id = (a->>'municipio_id')::integer
                 and delegados._norm(m.nombre) = delegados._norm(p_clave)));
  end if;

  if not v_ok then
    return jsonb_build_object('error',
      'Ese territorio está fuera de tu alcance. Tu consulta cubre: ' || (a->>'etiqueta') || '.');
  end if;

  if p_nivel = 'region' then
    with cnt as (select municipio_id, count(*) c from postulantes_2028
                  where estado not in ('rechazado','no_aprobado') group by municipio_id)
    select jsonb_build_object('nivel','region','nombre', min(x.macroregion),
             'meta', sum(x.meta), 'total', coalesce(sum(cnt.c),0),
             'hijos', (select jsonb_agg(jsonb_build_object('nombre', y.provincia_nombre, 'meta', y.m, 'total', y.t) order by y.m desc)
                       from (select b.provincia_nombre, sum(b.meta) m, coalesce(sum(c2.c),0) t
                               from portal_metas_municipio b
                               left join cnt c2 on c2.municipio_id = b.municipio_id
                              where delegados._norm(b.macroregion) = delegados._norm(p_clave)
                                and (b.estatus is null or b.estatus<>'I')
                              group by b.provincia_nombre) y))
      into v
      from portal_metas_municipio x
      left join cnt on cnt.municipio_id = x.municipio_id
     where delegados._norm(x.macroregion) = delegados._norm(p_clave)
       and (x.estatus is null or x.estatus<>'I')
    having count(x.municipio_id) > 0;

  elsif p_nivel = 'provincia' then
    with cnt as (select municipio_id, count(*) c from postulantes_2028
                  where estado not in ('rechazado','no_aprobado') group by municipio_id)
    select jsonb_build_object('nivel','provincia','nombre', min(x.provincia_nombre),
             'meta', sum(x.meta), 'total', coalesce(sum(cnt.c),0),
             'hijos', (select jsonb_agg(jsonb_build_object('nombre', y.nombre, 'meta', y.meta, 'total', y.t) order by y.meta desc)
                       from (select b.nombre, b.meta, coalesce(c2.c,0) t
                               from portal_metas_municipio b
                               left join cnt c2 on c2.municipio_id = b.municipio_id
                              where delegados._norm(b.provincia_nombre) = delegados._norm(p_clave)
                                and (b.estatus is null or b.estatus<>'I')) y))
      into v
      from portal_metas_municipio x
      left join cnt on cnt.municipio_id = x.municipio_id
     where delegados._norm(x.provincia_nombre) = delegados._norm(p_clave)
       and (x.estatus is null or x.estatus<>'I')
    having count(x.municipio_id) > 0;

  else
    select jsonb_build_object('nivel','municipio','nombre',x.nombre,'provincia',x.provincia_nombre,
             'region',x.macroregion,'meta',x.meta,
             'total',(select count(*) from postulantes_2028 p where p.municipio_id=x.municipio_id and p.estado not in ('rechazado','no_aprobado')),
             'distritos',(select jsonb_agg(jsonb_build_object('nombre',d.nombre,'es_dm',d.es_dm,'meta',d.meta,
                            'total',(select count(*) from postulantes_2028 p3
                                      join delegados._colegio_distrito c3 on c3.id_colegio=p3.colegio_asignado
                                     where c3.jce_distrito=d.jce_id
                                       and p3.estado not in ('rechazado','no_aprobado'))) order by d.es_dm, d.nombre)
                          from portal_distritos d where d.municipio_id=x.municipio_id),
             'cobertura',(select jsonb_build_object('completos',count(*) filter (where q.n>=3),
                                                    'parciales',count(*) filter (where q.n>0 and q.n<3),
                                                    'vacios',count(*) filter (where q.n=0))
                          from (select cd.id_colegio, count(p4.id) filter (where p4.estado not in ('rechazado','no_aprobado')) n
                                  from delegados._unidades_jce u
                                  join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
                                  left join postulantes_2028 p4 on p4.colegio_asignado=cd.id_colegio
                                 where u.municipio_id=x.municipio_id group by cd.id_colegio) q))
      into v
      from portal_metas_municipio x
     where delegados._norm(x.nombre) = delegados._norm(p_clave)
       and (x.estatus is null or x.estatus<>'I')
     limit 1;
  end if;

  return coalesce(v, jsonb_build_object('error','No encontré ese territorio. Verifica el nombre.'));
end $$;

-- ── 4. portal_bot_resumen (versión con cédula) ──
create or replace function delegados.portal_bot_resumen(p_cedula text default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare a jsonb; v jsonb; v_nivel text;
begin
  a := portal_bot_alcance(p_cedula);
  v_nivel := a->>'nivel';

  if v_nivel = 'nacional' then
    with base as (select * from portal_metas_municipio where estatus is null or estatus <> 'I'),
    cnt as (select municipio_id, count(*) c from postulantes_2028
             where estado not in ('rechazado','no_aprobado') group by municipio_id),
    reg as (select b.macroregion, sum(b.meta) meta, coalesce(sum(cnt.c),0) total
              from base b left join cnt on cnt.municipio_id = b.municipio_id group by b.macroregion),
    cole as (select cd.id_colegio,
                    count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) personas
               from base b
               join delegados._unidades_jce u on u.municipio_id = b.municipio_id
               join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
               left join postulantes_2028 p on p.colegio_asignado = cd.id_colegio
              group by cd.id_colegio)
    select jsonb_build_object(
      'alcance','Todo el país',
      'meta', (select sum(meta) from reg), 'total', (select sum(total) from reg),
      'colegios', (select count(*) from cole),
      'completos', (select count(*) from cole where personas >= 3),
      'parciales', (select count(*) from cole where personas > 0 and personas < 3),
      'vacios',    (select count(*) from cole where personas = 0),
      'regiones', (select jsonb_agg(jsonb_build_object('region', macroregion, 'meta', meta, 'total', total)
                                    order by meta desc) from reg)
    ) into v;

  elsif v_nivel = 'distrito' then
    with cole as (
      select cd.id_colegio,
             count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) personas
        from delegados._colegio_distrito cd
        left join postulantes_2028 p on p.colegio_asignado = cd.id_colegio
       where cd.jce_distrito = (a->>'jce_id')::integer
       group by cd.id_colegio)
    select jsonb_build_object(
      'alcance', a->>'etiqueta',
      'meta', count(*) * 3, 'total', coalesce(sum(personas),0), 'colegios', count(*),
      'completos', count(*) filter (where personas >= 3),
      'parciales', count(*) filter (where personas > 0 and personas < 3),
      'vacios',    count(*) filter (where personas = 0)
    ) into v from cole;

  else
    with base as (
      select * from portal_metas_municipio
       where (estatus is null or estatus <> 'I')
         and ((v_nivel = 'region'    and macroregion  = (a->>'region'))
           or (v_nivel = 'provincia' and provincia_id = (a->>'provincia_id')::integer)
           or (v_nivel = 'municipio' and municipio_id = (a->>'municipio_id')::integer))),
    cnt as (select municipio_id, count(*) c from postulantes_2028
             where estado not in ('rechazado','no_aprobado') group by municipio_id),
    cole as (select cd.id_colegio,
                    count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) personas
               from base b
               join delegados._unidades_jce u on u.municipio_id = b.municipio_id
               join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
               left join postulantes_2028 p on p.colegio_asignado = cd.id_colegio
              group by cd.id_colegio),
    hijos as (select b.nombre, b.meta, coalesce(c.c,0) total
                from base b left join cnt c on c.municipio_id = b.municipio_id
               order by b.meta desc limit 25)
    select jsonb_build_object(
      'alcance', a->>'etiqueta',
      'meta', (select coalesce(sum(meta),0) from base),
      'total', (select coalesce(sum(c),0) from cnt join base using (municipio_id)),
      'colegios', (select count(*) from cole),
      'completos', (select count(*) from cole where personas >= 3),
      'parciales', (select count(*) from cole where personas > 0 and personas < 3),
      'vacios',    (select count(*) from cole where personas = 0),
      'municipios', (select jsonb_agg(jsonb_build_object('nombre', nombre, 'meta', meta, 'total', total)) from hijos)
    ) into v;
  end if;

  return v;
end $$;

-- Comprobación (sin sesión): ninguna de las cuatro debe seguir usando id_colegio_padron.
-- Esperado: 4 filas con ok = true.
select p.proname, p.pronargs,
       pg_get_functiondef(p.oid) not like '%id_colegio_padron%' as ok
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'delegados'
   and ((p.proname = 'portal_kpi_filtro')
     or (p.proname = 'portal_kpi_distritos')
     or (p.proname = 'portal_bot_nivel'   and p.pronargs = 3)
     or (p.proname = 'portal_bot_resumen' and p.pronargs = 1))
 order by 1;
