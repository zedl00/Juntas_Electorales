-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 18
--  EMPAREJAMIENTO DE DISTRITOS ELEVADOS A MUNICIPIO · DIAGNÓSTICO OCLEE
-- ----------------------------------------------------------------
--  CAUSA ENCONTRADA: las demarcaciones de distrito se llaman
--  «LA VICTORIA (DM)» en la JCE, con el sufijo (DM). La comparación
--  de nombres no lo quitaba, así que ningún distrito elevado a
--  municipio lograba emparejarse. Ahora el sufijo se descarta antes
--  de comparar.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Requiere fase17.
-- ================================================================

set search_path = delegados, public;

-- Nombre normalizado sin el sufijo (DM)
create or replace function delegados._norm_dm(t text) returns text
language sql immutable as $$
  select delegados._norm(regexp_replace(coalesce(t,''), '\s*\(DM\)\s*$', '', 'i'))
$$;

drop view if exists delegados.portal_circ_municipio cascade;
drop view if exists delegados.portal_circunscripciones cascade;
drop view if exists delegados._colegio_full cascade;
drop view if exists delegados.portal_distritos cascade;
drop view if exists delegados.portal_metas_municipio cascade;
drop view if exists delegados._unidades_jce cascade;
drop view if exists delegados._par_municipio cascade;

create view delegados._par_municipio as
with n_app as (
  select m.id, delegados._norm(m.nombre) nom
    from public.municipios m where coalesce(m.tipo,'') <> 'OCLEE'
),
n_jce as (
  select jm.id, delegados._norm_dm(jm.descripcion) nom,
         (jm.id_municipio_padre is not null and jm.id_municipio_padre <> jm.id) es_dm
    from public.jce_municipio jm
),
cab as (select * from n_jce where not es_dm),
dm  as (select * from n_jce where es_dm),
cand as (
  select mn.municipio_id, mn.jce_id, 0 prio from delegados.mapeo_manual mn
  union all
  select ap.id, c.id, 1 from n_app ap join cab c on c.id = ap.id and c.nom = ap.nom
  union all
  select ap.id, c.id, 2 from n_app ap join cab c on c.nom = ap.nom
   where (select count(*) from cab c2  where c2.nom = ap.nom) = 1
     and (select count(*) from n_app a2 where a2.nom = ap.nom) = 1
  union all
  select ap.id, c.id, 3 from n_app ap join cab c on c.id = ap.id
  union all
  -- 4 · el municipio de la aplicación es un distrito en la JCE (sin el sufijo (DM))
  select ap.id, d.id, 4 from n_app ap join dm d on d.nom = ap.nom
   where (select count(*) from dm d2 where d2.nom = ap.nom) = 1
  union all
  select mm.id_actual, c.id, 5
    from public._mapeo_municipio mm
    join n_app ap on ap.id = mm.id_actual
    join cab c on c.id = mm.id_jce
),
p1 as (select distinct on (municipio_id) municipio_id, jce_id, prio
         from cand order by municipio_id, prio, jce_id),
p2 as (select distinct on (jce_id) municipio_id, jce_id, prio
         from p1 order by jce_id, prio, municipio_id)
select p2.municipio_id, p2.jce_id, p2.prio,
       (jm.id_municipio_padre is not null and jm.id_municipio_padre <> jm.id) as es_dm_propio
  from p2 join public.jce_municipio jm on jm.id = p2.jce_id;

alter view delegados._par_municipio owner to postgres;
grant select on delegados._par_municipio to authenticated, service_role;

create view delegados._unidades_jce as
select pm.municipio_id, pm.jce_id,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text as nombre,
       pm.es_dm_propio as es_dm
  from delegados._par_municipio pm
  join public.jce_municipio jm on jm.id = pm.jce_id
union all
select pm.municipio_id, jm.id::integer,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text,
       true
  from delegados._par_municipio pm
  join public.jce_municipio jm
    on jm.id_municipio_padre = pm.jce_id and jm.id <> pm.jce_id
 where not pm.es_dm_propio
   and not exists (select 1 from delegados._par_municipio p2 where p2.jce_id = jm.id);

alter view delegados._unidades_jce owner to postgres;
grant select on delegados._unidades_jce to authenticated, service_role;

create view delegados.portal_metas_municipio as
with col as (
  select u.municipio_id, cd.id_colegio, cd.id_recinto
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  union
  select municipio_id, id_colegio, id_recinto from delegados._colegio_oclee
)
select m.id as municipio_id, m.nombre, m.provincia_id,
       coalesce(nullif(btrim(m.provincia_nombre), ''), p.nombre) as provincia_nombre,
       case when m.tipo = 'OCLEE' then 'Exterior'
            else coalesce(nullif(btrim(p.macroregion), ''), nullif(btrim(m.macroregion), ''),
                          jr.descripcion::text, 'Sin región') end as macroregion,
       m.tipo, m.estatus,
       count(distinct col.id_colegio)             as colegios,
       count(distinct col.id_recinto)             as recintos,
       coalesce(sum(distinct c2.cantidad_inscritos), 0) as electores,
       count(distinct col.id_colegio) * 3         as meta,
       false as es_dm, m.id_municipio_padre as municipio_padre_id, m.tipo as provincia_tipo
from public.municipios m
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join col on col.municipio_id = m.id
left join public.jce_colegio c2 on c2.id_colegio = col.id_colegio
group by m.id, p.macroregion, p.nombre, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

create view delegados.portal_distritos as
select u.municipio_id, u.jce_id, u.nombre, u.es_dm,
       count(distinct cd.id_colegio) as colegios, count(distinct cd.id_recinto) as recintos,
       coalesce(sum(c.cantidad_inscritos), 0) as electores,
       count(distinct cd.id_colegio) * 3 as meta
from delegados._unidades_jce u
left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
left join public.jce_colegio c on c.id_colegio = cd.id_colegio
group by u.municipio_id, u.jce_id, u.nombre, u.es_dm;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

create view delegados._colegio_full as
select u.municipio_id, v.provincia_id, v.macroregion, v.tipo, v.estatus,
       u.jce_id, cd.circ_id, cd.id_recinto, cd.id_colegio,
       coalesce(c.cantidad_inscritos,0) as inscritos
  from delegados._unidades_jce u
  join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  join public.jce_colegio c on c.id_colegio = cd.id_colegio
  join delegados.portal_metas_municipio v on v.municipio_id = u.municipio_id
union all
select co.municipio_id, v.provincia_id, v.macroregion, v.tipo, v.estatus,
       null::integer, null::integer, co.id_recinto, co.id_colegio,
       coalesce(c.cantidad_inscritos,0)
  from delegados._colegio_oclee co
  join public.jce_colegio c on c.id_colegio = co.id_colegio
  join delegados.portal_metas_municipio v on v.municipio_id = co.municipio_id;

alter view delegados._colegio_full owner to postgres;
grant select on delegados._colegio_full to authenticated, service_role;

create view delegados.portal_circ_municipio as
select f.municipio_id, f.provincia_id, ci.id::integer as circ_id,
       coalesce(nullif(btrim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct f.id_colegio) as colegios, count(distinct f.id_colegio)*3 as meta
  from delegados._colegio_full f
  join public.jce_circunscripcion ci on ci.id = f.circ_id
 group by f.municipio_id, f.provincia_id, ci.id, ci.descripcion, ci.codigo_circunscripcion
union all
select u.municipio_id, null::integer, null::integer, u.circ_nombre,
       count(distinct co.id_colegio), count(distinct co.id_colegio)*3
  from delegados._unidades_oclee u
  join delegados._colegio_oclee co on co.oclee_id = u.oclee_id
 group by u.municipio_id, u.circ_nombre;

alter view delegados.portal_circ_municipio owner to postgres;
revoke all on delegados.portal_circ_municipio from anon;
grant select on delegados.portal_circ_municipio to authenticated, service_role;

create view delegados.portal_circunscripciones as
with divididos as (
  select municipio_id from delegados.portal_circ_municipio
   where circ_id is not null group by municipio_id having count(*) > 1
)
select c.municipio_id, c.circ_id, c.nombre, c.colegios, c.meta
  from delegados.portal_circ_municipio c join divididos d on d.municipio_id = c.municipio_id;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

-- ----------------------------------------------------------------
--  DIAGNÓSTICO: por qué faltan OCLEE en el listado
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag_oclee() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'oclee_en_app',      (select count(*) from public.municipios where coalesce(tipo,'') = 'OCLEE'),
    'oclee_activas',     (select count(*) from public.municipios
                           where coalesce(tipo,'') = 'OCLEE' and (estatus is null or estatus <> 'I')),
    'oclee_inactivas',   (select jsonb_agg(nombre order by nombre) from public.municipios
                           where coalesce(tipo,'') = 'OCLEE' and estatus = 'I'),
    'oclee_sin_colegios',(select jsonb_agg(v.nombre order by v.nombre)
                            from portal_metas_municipio v
                           where coalesce(v.tipo,'') = 'OCLEE' and v.colegios = 0),
    'meta_exterior',     (select sum(meta) from portal_metas_municipio where coalesce(tipo,'') = 'OCLEE'),
    'distritos_elevados',(select jsonb_agg(x) from (
                            select jsonb_build_object('municipio', m.nombre, 'jce_id', pm.jce_id,
                                     'evidencia', pm.prio,
                                     'colegios', (select count(*) from delegados._colegio_distrito cd
                                                   where cd.jce_distrito = pm.jce_id)) x
                              from public.municipios m
                              left join delegados._par_municipio pm on pm.municipio_id = m.id
                             where m.nombre in ('La Caleta','La Victoria','Tireo','Villa Central')) y),
    'meta_nacional',     (select sum(meta) from portal_metas_municipio
                           where coalesce(tipo,'') <> 'OCLEE' and (estatus is null or estatus <> 'I'))
  );
$$;

revoke all on function delegados.portal_diag_oclee() from public, anon;
grant execute on function delegados.portal_diag_oclee() to authenticated;

notify pgrst, 'reload schema';

-- ── PENDIENTES A REGISTRAR A MANO ──
--  Tireo: la JCE lo llama «TIREO ARRIBA (DM)» (jce 163)
--    insert into delegados.mapeo_manual (municipio_id, jce_id, nota)
--    values (902, 163, 'Tireo = TIREO ARRIBA (DM)');
--
--  La Caleta: hay DOS con ese nombre (jce 286 padre 226 · jce 360 padre 26).
--    Ver cuál es el correcto y registrarlo:
--    select id, descripcion from public.jce_municipio where id in (226, 26);
--    insert into delegados.mapeo_manual (municipio_id, jce_id, nota)
--    values (903, <el que corresponda>, 'La Caleta');
--
--  Filadelfia (OCLEE):
--    insert into delegados.mapeo_manual (municipio_id, jce_id, nota)
--    values (911, 19, 'Filadelfia = PHILADELPHIA');
