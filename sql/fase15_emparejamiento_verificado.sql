-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 15
--  EMPAREJAMIENTO VERIFICADO · CIRCUNSCRIPCIONES EN SUS DOS USOS
-- ----------------------------------------------------------------
--  HALLAZGOS (diagnóstico del 25/08, datos reales):
--   1. _mapeo_municipio NO es confiable: mapea el municipio app 1
--      (Santo Domingo de Guzmán) a la demarcación JCE 126 (Tábara
--      Arriba). Las fases anteriores le daban prioridad sobre la
--      coincidencia por identidad y nombre → distritos cruzados.
--      Ahora el mapeo pasa a ÚLTIMO recurso, y solo se acepta si
--      la demarcación no fue reclamada por evidencia más fuerte.
--   2. La circunscripción tiene dos usos: subdivide un municipio
--      (Distrito Nacional, Santiago, Santo Domingo Este, San Antonio
--      de Guerra) y agrupa municipios dentro de una provincia (9
--      provincias). Se exponen ambos.
--   3. El exterior usa códigos de texto ('01','02','03') en
--      jce_oclee.id_circunscripcion — no una llave numérica.
--
--  NO se modifica ninguna tabla de public. Solo vistas y funciones
--  del esquema delegados. EJECUTAR COMPLETO, DE UNA SOLA VEZ.
-- ================================================================

set search_path = delegados, public;

-- Normalizador de nombres (acentos, mayúsculas, espacios)
create or replace function delegados._norm(t text) returns text
language sql immutable as $$
  select upper(btrim(regexp_replace(
    translate(coalesce(t,''), 'ÁÉÍÓÚÜÑÀÈÌÒÙáéíóúüñàèìòù', 'AEIOUUNAEIOUaeiouunaeiou'),
    '\s+', ' ', 'g')))
$$;

-- ----------------------------------------------------------------
-- 1. EMPAREJAMIENTO app ↔ JCE por evidencia, no por suposición
-- ----------------------------------------------------------------
drop view if exists delegados.portal_circ_municipio cascade;
drop view if exists delegados.portal_circunscripciones cascade;
drop view if exists delegados.portal_distritos cascade;
drop view if exists delegados.portal_metas_municipio cascade;
drop view if exists delegados._unidades_jce cascade;
drop view if exists delegados._par_municipio cascade;

create view delegados._par_municipio as
with n_app as (
  select m.id, delegados._norm(m.nombre) nom
    from public.municipios m
   where coalesce(m.tipo,'') <> 'OCLEE'
),
n_jce as (
  select jm.id, delegados._norm(jm.descripcion) nom,
         (jm.id_municipio_padre is not null and jm.id_municipio_padre <> jm.id) es_dm
    from public.jce_municipio jm
),
cab as (select * from n_jce where not es_dm),
cand as (
  -- A · mismo id Y mismo nombre: certeza máxima
  select ap.id municipio_id, c.id jce_id, 1 prio
    from n_app ap join cab c on c.id = ap.id and c.nom = ap.nom
  union all
  -- B · nombre coincidente y único en ambos lados
  select ap.id, c.id, 2
    from n_app ap join cab c on c.nom = ap.nom
   where (select count(*) from cab c2  where c2.nom = ap.nom) = 1
     and (select count(*) from n_app a2 where a2.nom = ap.nom) = 1
  union all
  -- C · mismo id aunque el nombre difiera (variantes de escritura)
  select ap.id, c.id, 3 from n_app ap join cab c on c.id = ap.id
  union all
  -- D · último recurso: la tabla de mapeo
  select mm.id_actual, c.id, 4
    from public._mapeo_municipio mm
    join n_app ap on ap.id = mm.id_actual
    join cab c on c.id = mm.id_jce
),
p1 as (select distinct on (municipio_id) municipio_id, jce_id, prio
         from cand order by municipio_id, prio, jce_id),
p2 as (select distinct on (jce_id) municipio_id, jce_id, prio
         from p1 order by jce_id, prio, municipio_id)
select * from p2;

alter view delegados._par_municipio owner to postgres;
grant select on delegados._par_municipio to authenticated, service_role;

-- Demarcaciones de cada municipio: su cabecera + sus distritos municipales
create view delegados._unidades_jce as
select pm.municipio_id, pm.jce_id,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text as nombre,
       false as es_dm
  from delegados._par_municipio pm
  join public.jce_municipio jm on jm.id = pm.jce_id
union all
select pm.municipio_id, jm.id::integer,
       initcap(lower(regexp_replace(coalesce(jm.descripcion,''), '\s*\(DM\)\s*$', '')))::text,
       true
  from delegados._par_municipio pm
  join public.jce_municipio jm
    on jm.id_municipio_padre = pm.jce_id and jm.id <> pm.jce_id;

alter view delegados._unidades_jce owner to postgres;
grant select on delegados._unidades_jce to authenticated, service_role;

-- ----------------------------------------------------------------
-- 2. EXTERIOR: oficinas OCLEE con su circunscripción de texto
-- ----------------------------------------------------------------
drop view if exists delegados._colegio_oclee cascade;
drop view if exists delegados._unidades_oclee cascade;

create view delegados._unidades_oclee as
select distinct on (m.id)
       m.id::integer            as municipio_id,
       o.id::integer            as oclee_id,
       o.id_municipio::integer  as jce_id,
       lpad(btrim(coalesce(o.id_circunscripcion::text,'')), 2, '0') as circ_codigo,
       case lpad(btrim(coalesce(o.id_circunscripcion::text,'')), 2, '0')
         when '01' then '1ra Circunscripción — Estados Unidos y Canadá'
         when '02' then '2da Circunscripción — América Latina y el Caribe'
         when '03' then '3ra Circunscripción — Europa y resto del mundo'
         else 'Circunscripción exterior' end::text as circ_nombre,
       initcap(lower(o.descripcion))::text as nombre
  from public.municipios m
  join public.jce_oclee o on delegados._norm(o.descripcion) = delegados._norm(m.nombre)
 where coalesce(m.tipo,'') = 'OCLEE'
 order by m.id, o.id;

alter view delegados._unidades_oclee owner to postgres;
grant select on delegados._unidades_oclee to authenticated, service_role;

-- Colegios del exterior: de la demarcación de la oficina.
-- Si varias oficinas comparten demarcación, se reparten por recinto
-- (cada recinto pertenece a una sola oficina).
create view delegados._colegio_oclee as
select u.municipio_id, u.oclee_id, c.id_colegio::integer, c.id_recinto::integer
  from delegados._unidades_oclee u
  join public.jce_colegio c on c.id_municipio = u.jce_id
 where not exists (                       -- evita duplicar si comparten demarcación
   select 1 from delegados._unidades_oclee u2
    where u2.jce_id = u.jce_id and u2.oclee_id < u.oclee_id
 )
 union
select u.municipio_id, u.oclee_id, c.id_colegio::integer, c.id_recinto::integer
  from delegados._unidades_oclee u
  join public.jce_recinto rc on delegados._norm(rc.descripcion) like '%' || delegados._norm(u.nombre) || '%'
  join public.jce_colegio c on c.id_recinto = rc.id;

alter view delegados._colegio_oclee owner to postgres;
grant select on delegados._colegio_oclee to authenticated, service_role;

-- ----------------------------------------------------------------
-- 3. METAS (nacional por unidades JCE · exterior por OCLEE)
-- ----------------------------------------------------------------
create view delegados.portal_metas_municipio as
with col as (
  select u.municipio_id, cd.id_colegio, cd.id_recinto
    from delegados._unidades_jce u
    join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  union
  select municipio_id, id_colegio, id_recinto from delegados._colegio_oclee
)
select m.id            as municipio_id,
       m.nombre,
       m.provincia_id,
       coalesce(nullif(btrim(m.provincia_nombre), ''), p.nombre) as provincia_nombre,
       case when m.tipo = 'OCLEE' then 'Exterior'
            else coalesce(nullif(btrim(p.macroregion), ''), nullif(btrim(m.macroregion), ''),
                          jr.descripcion::text, 'Sin región')
       end                                        as macroregion,
       m.tipo, m.estatus,
       count(distinct col.id_colegio)             as colegios,
       count(distinct col.id_recinto)             as recintos,
       coalesce(sum(distinct c2.cantidad_inscritos), 0) as electores,
       count(distinct col.id_colegio) * 3         as meta,
       false                                      as es_dm,
       m.id_municipio_padre                       as municipio_padre_id,
       m.tipo                                     as provincia_tipo
from public.municipios m
left join public.provincias p  on p.id = m.provincia_id
left join public.jce_region jr on jr.id = p.region_id
left join col on col.municipio_id = m.id
left join public.jce_colegio c2 on c2.id_colegio = col.id_colegio
group by m.id, p.macroregion, p.nombre, jr.descripcion;

alter view delegados.portal_metas_municipio owner to postgres;
revoke all on delegados.portal_metas_municipio from anon;
grant select on delegados.portal_metas_municipio to authenticated, service_role;

-- ----------------------------------------------------------------
-- 4. DISTRITOS (solo territorio nacional)
-- ----------------------------------------------------------------
create view delegados.portal_distritos as
select u.municipio_id, u.jce_id, u.nombre, u.es_dm,
       count(distinct cd.id_colegio)             as colegios,
       count(distinct cd.id_recinto)             as recintos,
       coalesce(sum(c.cantidad_inscritos), 0)    as electores,
       count(distinct cd.id_colegio) * 3         as meta
from delegados._unidades_jce u
left join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
left join public.jce_colegio c on c.id_colegio = cd.id_colegio
group by u.municipio_id, u.jce_id, u.nombre, u.es_dm;

alter view delegados.portal_distritos owner to postgres;
revoke all on delegados.portal_distritos from anon;
grant select on delegados.portal_distritos to authenticated, service_role;

-- ----------------------------------------------------------------
-- 5. CIRCUNSCRIPCIONES · los dos usos reales
--    portal_circ_municipio: todas las circunscripciones de cada
--      municipio (subdivisión interna o pertenencia provincial).
--    portal_circunscripciones: compatibilidad — solo las que
--      efectivamente subdividen un municipio.
-- ----------------------------------------------------------------
create view delegados.portal_circ_municipio as
select v.municipio_id, v.provincia_id, ci.id::integer as circ_id,
       coalesce(nullif(btrim(ci.descripcion),''),
                'Circunscripción ' || ci.codigo_circunscripcion)::text as nombre,
       count(distinct cd.id_colegio)   as colegios,
       count(distinct cd.id_colegio)*3 as meta
  from delegados._unidades_jce u
  join delegados._colegio_distrito cd on cd.jce_distrito = u.jce_id
  join public.jce_circunscripcion ci on ci.id = cd.circ_id
  join delegados.portal_metas_municipio v on v.municipio_id = u.municipio_id
 group by v.municipio_id, v.provincia_id, ci.id, ci.descripcion, ci.codigo_circunscripcion
union all
select u.municipio_id, null::integer, null::integer,
       u.circ_nombre, count(distinct co.id_colegio), count(distinct co.id_colegio)*3
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
  from delegados.portal_circ_municipio c
  join divididos d on d.municipio_id = c.municipio_id;

alter view delegados.portal_circunscripciones owner to postgres;
revoke all on delegados.portal_circunscripciones from anon;
grant select on delegados.portal_circunscripciones to authenticated, service_role;

notify pgrst, 'reload schema';

-- ----------------------------------------------------------------
-- 6. DIAGNÓSTICO: evidencia del emparejamiento y de los cruces
-- ----------------------------------------------------------------
create or replace function delegados.portal_diag() returns jsonb
language sql stable security definer set search_path = delegados, public as $$
  select jsonb_build_object(
    'municipios_app',     (select count(*) from public.municipios where coalesce(tipo,'') <> 'OCLEE'),
    'emparejados',        (select count(*) from delegados._par_municipio),
    'por_evidencia',      (select jsonb_object_agg(prio, n) from
                            (select prio, count(*) n from delegados._par_municipio group by prio) x),
    'sin_emparejar',      (select jsonb_agg(m.nombre order by m.nombre) from public.municipios m
                            where coalesce(m.tipo,'') <> 'OCLEE'
                              and not exists (select 1 from delegados._par_municipio pm
                                               where pm.municipio_id = m.id)),
    'distritos',          (select count(*) from portal_distritos where es_dm),
    'muns_con_distritos', (select count(*) from (select municipio_id from portal_distritos
                                                  group by municipio_id having count(*) > 1) x),
    'colegios_total',     (select count(*) from public.jce_colegio),
    'colegios_ubicados',  (select count(distinct cd.id_colegio) from delegados._colegio_distrito cd
                             join delegados._unidades_jce u on u.jce_id = cd.jce_distrito),
    'meta_nacional',      (select sum(meta) from portal_metas_municipio
                            where coalesce(tipo,'') <> 'OCLEE' and (estatus is null or estatus <> 'I')),
    'meta_exterior',      (select sum(meta) from portal_metas_municipio where coalesce(tipo,'') = 'OCLEE'),
    'oclee_enlazadas',    (select count(*) from delegados._unidades_oclee),
    'oclee_sin_enlace',   (select jsonb_agg(m.nombre order by m.nombre) from public.municipios m
                            where coalesce(m.tipo,'') = 'OCLEE'
                              and not exists (select 1 from delegados._unidades_oclee u
                                               where u.municipio_id = m.id)),
    'muns_subdivididos',  (select jsonb_agg(x) from (
                            select jsonb_build_object('municipio', v.nombre, 'circs', c.n) x
                              from (select municipio_id, count(*) n from delegados.portal_circ_municipio
                                     where circ_id is not null group by municipio_id having count(*) > 1) c
                              join portal_metas_municipio v on v.municipio_id = c.municipio_id) y),
    'provincias_con_circ',(select count(*) from (
                            select provincia_id from delegados.portal_circ_municipio
                             where circ_id is not null and provincia_id is not null
                             group by provincia_id having count(distinct circ_id) > 1) z)
  );
$$;

revoke all on function delegados.portal_diag() from public, anon;
grant execute on function delegados.portal_diag() to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  select jsonb_pretty(delegados.portal_diag());
--  Esperado: emparejados ≈ 162 · sin_emparejar vacío o muy corto ·
--            colegios_ubicados = colegios_total · muns_subdivididos con
--            Distrito Nacional, Santiago, Santo Domingo Este y San Antonio de Guerra.
