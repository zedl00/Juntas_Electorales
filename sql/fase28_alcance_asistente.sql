-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 28
--  EL ASISTENTE RESPETA EL ALCANCE TERRITORIAL DE CADA USUARIO
-- ----------------------------------------------------------------
--  Hasta ahora cualquier autorizado veía las cifras nacionales.
--  Con el acceso enlazado a un usuario del portal, el asistente
--  aplica el mismo alcance que rige dentro del sistema:
--    · admin_sne / consulta_nacional → todo el país
--    · coordinador_regional          → su región
--    · supervisor_provincial         → su provincia
--    · presidente / secretario / enc → su municipio (o su distrito)
--    · acceso sin enlazar            → todo el país (externo autorizado)
--
--  EJECUTAR COMPLETO. Requiere fase27.
-- ================================================================

set search_path = delegados, public;

-- ── Alcance de un acceso, a partir de la cédula enlazada ──
create or replace function delegados.portal_bot_alcance(p_cedula text)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare u record; v_dist text;
begin
  if p_cedula is null or btrim(p_cedula) = '' then
    return jsonb_build_object('nivel','nacional','etiqueta','Todo el país');
  end if;

  select * into u from usuarios_territoriales
   where cedula = regexp_replace(p_cedula,'\D','','g') and activo;
  if not found then
    return jsonb_build_object('nivel','nacional','etiqueta','Todo el país');
  end if;

  if u.rol in ('admin_sne','consulta_nacional') then
    return jsonb_build_object('nivel','nacional','etiqueta','Todo el país');
  elsif u.rol = 'coordinador_regional' then
    return jsonb_build_object('nivel','region','region', u.region,
                              'etiqueta','Región ' || coalesce(u.region,''));
  elsif u.rol = 'supervisor_provincial' then
    return jsonb_build_object('nivel','provincia','provincia_id', u.provincia_id,
                              'etiqueta', coalesce((select nombre from public.provincias where id = u.provincia_id),'Tu provincia'));
  else
    if u.jce_id is not null then
      select nombre into v_dist from portal_distritos where jce_id = u.jce_id limit 1;
      return jsonb_build_object('nivel','distrito','municipio_id', u.municipio_id, 'jce_id', u.jce_id,
                                'etiqueta', coalesce(v_dist,'Tu distrito'));
    end if;
    return jsonb_build_object('nivel','municipio','municipio_id', u.municipio_id,
                              'etiqueta', coalesce((select nombre from portal_metas_municipio where municipio_id = u.municipio_id),'Tu municipio'));
  end if;
end $$;

revoke all on function delegados.portal_bot_alcance(text) from public, anon;
grant execute on function delegados.portal_bot_alcance(text) to service_role, authenticated;

-- ── Resumen: devuelve el territorio propio de quien consulta ──
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
               left join postulantes_2028 p on p.id_colegio_padron = cd.id_colegio and p.municipio_id = b.municipio_id
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
        left join postulantes_2028 p on p.id_colegio_padron = cd.id_colegio
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
               left join postulantes_2028 p on p.id_colegio_padron = cd.id_colegio and p.municipio_id = b.municipio_id
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

revoke all on function delegados.portal_bot_resumen(text) from public, anon;
grant execute on function delegados.portal_bot_resumen(text) to service_role;

-- ── Consulta por nivel: rechaza territorios fuera del alcance ──
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

  -- Dentro del alcance: se responde igual que antes
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
                                      join delegados._colegio_distrito c3 on c3.id_colegio=p3.id_colegio_padron
                                     where c3.jce_distrito=d.jce_id and p3.municipio_id=x.municipio_id
                                       and p3.estado not in ('rechazado','no_aprobado'))) order by d.es_dm, d.nombre)
                          from portal_distritos d where d.municipio_id=x.municipio_id),
             'cobertura',(select jsonb_build_object('completos',count(*) filter (where q.n>=3),
                                                    'parciales',count(*) filter (where q.n>0 and q.n<3),
                                                    'vacios',count(*) filter (where q.n=0))
                          from (select cd.id_colegio, count(p4.id) filter (where p4.estado not in ('rechazado','no_aprobado')) n
                                  from delegados._unidades_jce u
                                  join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
                                  left join postulantes_2028 p4 on p4.id_colegio_padron=cd.id_colegio and p4.municipio_id=x.municipio_id
                                 where u.municipio_id=x.municipio_id group by cd.id_colegio) q))
      into v
      from portal_metas_municipio x
     where delegados._norm(x.nombre) = delegados._norm(p_clave)
       and (x.estatus is null or x.estatus<>'I')
     limit 1;
  end if;

  return coalesce(v, jsonb_build_object('error','No encontré ese territorio. Verifica el nombre.'));
end $$;

revoke all on function delegados.portal_bot_nivel(text, text, text) from public, anon;
grant execute on function delegados.portal_bot_nivel(text, text, text) to service_role;

notify pgrst, 'reload schema';
