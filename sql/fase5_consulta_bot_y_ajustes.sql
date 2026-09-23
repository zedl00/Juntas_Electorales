-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 5 · ROL CONSULTA NACIONAL,
--  MILITANCIA EN EL EXPEDIENTE Y BOT DE CONSULTAS/PIN
-- ----------------------------------------------------------------
--  · Ejecutar DESPUÉS de fase1, fase2 y fase4. Idempotente.
-- ================================================================

set search_path = delegados, public;

-- 1 · Expediente: militancia partidaria (para captura e impresión)
alter table delegados.postulantes_2028 add column if not exists militancia text;

-- 2 · Nuevo rol: consulta_nacional (ve e imprime todo; no registra ni valida)
alter table delegados.usuarios_territoriales drop constraint if exists usuarios_territoriales_rol_check;
alter table delegados.usuarios_territoriales add constraint usuarios_territoriales_rol_check
  check (rol in ('presidente','secretario_general','enc_electoral',
                 'supervisor_provincial','coordinador_regional','consulta_nacional','admin_sne'));

drop policy if exists p28_select on delegados.postulantes_2028;
create policy p28_select on delegados.postulantes_2028
for select to authenticated using (
  delegados.portal_rol() in ('admin_sne','consulta_nacional')
  or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun())
  or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
  or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
);

-- Las cuatro funciones con alcance ganan el rol (alias interno a alcance nacional):
create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v_mun integer;
  v_prov integer;
  v_reg text;
  v jsonb;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  if v_rol in ('presidente','secretario_general','enc_electoral') then
    v_mun := portal_mun();
  elsif v_rol = 'supervisor_provincial' then
    v_prov := portal_prov(); v_mun := p_municipio;
  elsif v_rol = 'coordinador_regional' then
    v_reg := portal_region(); v_mun := p_municipio;
  else
    v_mun := p_municipio;  -- admin_sne
  end if;

  with alcance as (
    select v2.municipio_id, v2.colegios, v2.meta
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (v_mun  is null or v2.municipio_id = v_mun)
       and (v_prov is null or v2.provincia_id = v_prov)
       and (v_reg  is null or v2.macroregion = v_reg)
  ),
  pos as (
    select p.* from postulantes_2028 p
     where p.municipio_id in (select municipio_id from alcance)
  )
  select jsonb_build_object(
    'meta',      coalesce((select sum(meta) from alcance), 0),
    'colegios',  coalesce((select sum(colegios) from alcance), 0),
    'total',     (select count(*) from pos),
    'hoy',       (select count(*) from pos where created_at::date = current_date),
    'semana',    (select count(*) from pos where created_at >= now() - interval '7 days'),
    'con_experiencia', (select count(*) from pos where experiencia_2024),
    'colegios_cubiertos', (select count(distinct id_colegio_padron) from pos where id_colegio_padron is not null),
    'por_estado', coalesce((select jsonb_object_agg(estado, n)
                     from (select estado, count(*) n from pos group by estado) e), '{}'::jsonb),
    'por_cargo',  coalesce((select jsonb_object_agg(cargo_postulado, n)
                     from (select cargo_postulado, count(*) n from pos group by cargo_postulado) c2), '{}'::jsonb),
    'por_sexo',   coalesce((select jsonb_object_agg(coalesce(sexo,'?'), n)
                     from (select sexo, count(*) n from pos group by sexo) s2), '{}'::jsonb)
  ) into v;

  return v;
end $$;

create or replace function delegados.portal_kpi_territorios()
returns table (
  municipio_id integer, municipio text, provincia_id integer, provincia text,
  macroregion text, tipo text, colegios bigint, meta bigint,
  postulados bigint, validados bigint, en_formacion bigint,
  designados bigint, otros bigint, total bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  return query
  select v2.municipio_id, v2.nombre::text, v2.provincia_id, v2.provincia_nombre::text,
         v2.macroregion::text, v2.tipo::text, v2.colegios, v2.meta,
         count(*) filter (where p.estado = 'postulado'),
         count(*) filter (where p.estado = 'validado'),
         count(*) filter (where p.estado in ('en_formacion','aprobado')),
         count(*) filter (where p.estado in ('designado','acreditado')),
         count(*) filter (where p.estado in ('devuelto','rechazado','no_aprobado')),
         count(p.id)
    from portal_metas_municipio v2
    left join postulantes_2028 p on p.municipio_id = v2.municipio_id
   where (v2.estatus is null or v2.estatus <> 'I')
     and (
       v_rol = 'admin_sne'
       or (v_rol in ('presidente','secretario_general','enc_electoral')
           and v2.municipio_id = portal_mun())
       or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
       or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
     )
   group by v2.municipio_id, v2.nombre, v2.provincia_id, v2.provincia_nombre,
            v2.macroregion, v2.tipo, v2.colegios, v2.meta
   order by count(p.id) desc, v2.meta desc;
end $$;

create or replace function delegados.portal_cobertura_resumen()
returns table (
  municipio_id integer, colegios bigint, completos bigint, parciales bigint, vacios bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  return query
  with alcance as (
    select v2.municipio_id
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (
         v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and v2.municipio_id = portal_mun())
         or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
       )
  ),
  cole as (
    select a.municipio_id as mun_id, c.id_colegio,
           count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) as personas
      from alcance a
      join public._mapeo_municipio mm on mm.id_actual = a.municipio_id
      join public.jce_colegio c       on c.id_municipio = mm.id_jce
      left join postulantes_2028 p    on p.id_colegio_padron = c.id_colegio
                                     and p.municipio_id = a.municipio_id
     group by a.municipio_id, c.id_colegio
  )
  select cole.mun_id,
         count(*)::bigint,
         count(*) filter (where personas >= 3),
         count(*) filter (where personas > 0 and personas < 3),
         count(*) filter (where personas = 0)
    from cole
   group by cole.mun_id;
end $$;

create or replace function delegados.portal_cobertura_colegios(p_municipio integer, p_jce integer default null)
returns table (
  distrito text, jce_id integer,
  id_colegio integer, colegio text, recinto text, recinto_dir text,
  inscritos bigint, titulares bigint, suplentes bigint, observadores bigint,
  indistintos bigint, personas bigint
)
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
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
  select initcap(lower(coalesce(jm.descripcion, '—')))::text,
         jm.id::integer,
         c.id_colegio::integer,
         coalesce(nullif(trim(c.codigo_colegio),''), c.descripcion, 'Colegio '||c.id_colegio)::text,
         coalesce(rc.descripcion,'—')::text,
         coalesce(rc.direccion,'')::text,
         coalesce(sum(distinct c.cantidad_inscritos),0)::bigint,
         count(p.id) filter (where p.cargo_postulado = 'delegado_titular'      and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'suplente_delegado'     and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'observador_escrutinio' and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.cargo_postulado = 'indistinto'            and p.estado not in ('rechazado','no_aprobado')),
         count(p.id) filter (where p.estado not in ('rechazado','no_aprobado'))
    from public._mapeo_municipio mm
    join public.jce_municipio jm on jm.id = mm.id_jce
    join public.jce_colegio c    on c.id_municipio = jm.id
    left join public.jce_recinto rc on rc.id = c.id_recinto
    left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio
                                and p.municipio_id = p_municipio
   where mm.id_actual = p_municipio
     and (p_jce is null or jm.id = p_jce)
   group by jm.id, jm.descripcion, c.id_colegio, c.descripcion, rc.descripcion, rc.direccion
   order by 1, 5, 4;
end $$;

-- 3 · BOT (Telegram) · tabla de chats autorizados + consultas agregadas SIN nombres
create table if not exists delegados.bot_usuarios (
  chat_id     bigint primary key,
  cedula      text,
  descripcion text,
  rol         text not null default 'consulta' check (rol in ('consulta','admin')),
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table delegados.bot_usuarios enable row level security;
grant select, insert, update, delete on delegados.bot_usuarios to service_role;

create or replace function delegados.portal_bot_resumen()
returns jsonb language sql stable security definer set search_path = delegados, public as $$
  with base as (select * from portal_metas_municipio where estatus is null or estatus <> 'I'),
  cnt as (
    select municipio_id, count(*) c from postulantes_2028
     where estado not in ('rechazado','no_aprobado') group by municipio_id
  ),
  reg as (
    select b.macroregion, sum(b.meta) meta, coalesce(sum(cnt.c),0) total
      from base b left join cnt on cnt.municipio_id = b.municipio_id
     group by b.macroregion
  ),
  cole as (
    select c.id_colegio, count(p.id) filter (where p.estado not in ('rechazado','no_aprobado')) personas
      from base b
      join public._mapeo_municipio mm on mm.id_actual = b.municipio_id
      join public.jce_colegio c on c.id_municipio = mm.id_jce
      left join postulantes_2028 p on p.id_colegio_padron = c.id_colegio and p.municipio_id = b.municipio_id
     group by c.id_colegio
  )
  select jsonb_build_object(
    'meta', (select sum(meta) from reg),
    'total', (select sum(total) from reg),
    'colegios', (select count(*) from cole),
    'completos', (select count(*) from cole where personas >= 3),
    'parciales', (select count(*) from cole where personas > 0 and personas < 3),
    'vacios',    (select count(*) from cole where personas = 0),
    'regiones', (select jsonb_agg(jsonb_build_object('region', macroregion, 'meta', meta, 'total', total)
                                  order by meta desc) from reg)
  );
$$;

create or replace function delegados.portal_bot_nivel(p_nivel text, p_clave text)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare v jsonb;
begin
  if p_nivel = 'region' then
    with cnt as (select municipio_id, count(*) c from postulantes_2028
                  where estado not in ('rechazado','no_aprobado') group by municipio_id)
    select jsonb_build_object('nivel','region','nombre', min(x.macroregion),
             'meta', sum(x.meta), 'total', coalesce(sum(cnt.c),0),
             'hijos', (select jsonb_agg(jsonb_build_object('nombre', y.provincia_nombre, 'meta', y.m, 'total', y.t) order by y.m desc)
                       from (select b.provincia_nombre, sum(b.meta) m, coalesce(sum(c2.c),0) t
                               from portal_metas_municipio b
                               left join cnt c2 on c2.municipio_id = b.municipio_id
                              where b.macroregion ilike p_clave and (b.estatus is null or b.estatus<>'I')
                              group by b.provincia_nombre) y))
      into v
      from portal_metas_municipio x
      left join cnt on cnt.municipio_id = x.municipio_id
     where x.macroregion ilike p_clave and (x.estatus is null or x.estatus<>'I')
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
                              where b.provincia_nombre ilike p_clave and (b.estatus is null or b.estatus<>'I')) y))
      into v
      from portal_metas_municipio x
      left join cnt on cnt.municipio_id = x.municipio_id
     where x.provincia_nombre ilike p_clave and (x.estatus is null or x.estatus<>'I')
    having count(x.municipio_id) > 0;

    else
    select jsonb_build_object('nivel','municipio','nombre',x.nombre,'provincia',x.provincia_nombre,
             'region',x.macroregion,'meta',x.meta,
             'total',(select count(*) from postulantes_2028 p where p.municipio_id=x.municipio_id and p.estado not in ('rechazado','no_aprobado')),
             'distritos',(select jsonb_agg(jsonb_build_object('nombre',d.nombre,'es_dm',d.es_dm,'colegios',d.colegios,'meta',d.meta,
                            'total',(select count(*) from postulantes_2028 p3
                                      join public.jce_colegio c3 on c3.id_colegio=p3.id_colegio_padron
                                     where c3.id_municipio=d.jce_id and p3.municipio_id=x.municipio_id
                                       and p3.estado not in ('rechazado','no_aprobado'))) order by d.es_dm, d.nombre)
                          from portal_distritos d where d.municipio_id=x.municipio_id),
             'cobertura',(select jsonb_build_object('completos',count(*) filter (where q.n>=3),
                                                    'parciales',count(*) filter (where q.n>0 and q.n<3),
                                                    'vacios',count(*) filter (where q.n=0))
                          from (select c.id_colegio, count(p4.id) filter (where p4.estado not in ('rechazado','no_aprobado')) n
                                  from public._mapeo_municipio mm join public.jce_colegio c on c.id_municipio=mm.id_jce
                                  left join postulantes_2028 p4 on p4.id_colegio_padron=c.id_colegio and p4.municipio_id=x.municipio_id
                                 where mm.id_actual=x.municipio_id group by c.id_colegio) q))
      into v
      from portal_metas_municipio x
     where x.nombre ilike p_clave and (x.estatus is null or x.estatus<>'I')
     limit 1;
  end if;
  return coalesce(v, jsonb_build_object('error','No encontré ese territorio. Verifica el nombre.'));
end $$;

create or replace function delegados.portal_bot_reset_pin(p_cedula text, p_pin text)
returns jsonb language plpgsql volatile security definer
set search_path = delegados, public, extensions as $$
declare
  v_ced text := regexp_replace(coalesce(p_cedula,''), '\D', '', 'g');
  v_uid uuid; v_rol text; v_nombre text;
begin
  if length(coalesce(p_pin,'')) < 6 then raise exception 'PIN inválido'; end if;
  select id, rol, nombre into v_uid, v_rol, v_nombre from usuarios_territoriales where cedula = v_ced;
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'No existe usuario con esa cédula.'); end if;
  if v_rol = 'admin_sne' then return jsonb_build_object('ok', false, 'error', 'Las cuentas de administración se gestionan en el sistema SNE.'); end if;
  update auth.users set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')) where id = v_uid;
  if not found then return jsonb_build_object('ok', false, 'error', 'Cuenta de acceso no localizada.'); end if;
  update usuarios_territoriales set primer_acceso = true where id = v_uid;
  insert into eventos_sistema (usuario_id, accion, entidad, entidad_id, detalle)
  values (null, 'reset_pin', 'usuario', v_ced, jsonb_build_object('metodo','bot'));
  return jsonb_build_object('ok', true, 'nombre', v_nombre);
end $$;

revoke all on function delegados.portal_bot_resumen() from public, anon, authenticated;
revoke all on function delegados.portal_bot_nivel(text, text) from public, anon, authenticated;
revoke all on function delegados.portal_bot_reset_pin(text, text) from public, anon, authenticated;
grant execute on function delegados.portal_bot_resumen() to service_role;
grant execute on function delegados.portal_bot_nivel(text, text) to service_role;
grant execute on function delegados.portal_bot_reset_pin(text, text) to service_role;

notify pgrst, 'reload schema';
