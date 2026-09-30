-- fase84_vista_juntas_y_cedula.sql · Análisis Electoral (esquema public). Idempotente.
--
-- 1. Cédula en aspirantes, tomada de la resolución para cada aspirante emparejado.
-- 2. Foto de la selección de MAYO 2026 (303 personas marcadas antes del 1 jun 2026), guardada
--    aparte para que ninguna marca se pierda aunque después se cambie la tabla de aspirantes.
--    El cargo de mayo se toma del cargo al que aspiraba: así lo marcaba la aplicación.
-- 3. vista_juntas_2026: cada junta, cargo por cargo, quién quedó, partido, cómo se emparejó y
--    si esa persona ya estaba en la lista de mayo.
-- 4. vista_cambios_mayo_2026: cada persona de mayo y su situación frente a la resolución:
--    se mantiene · cambió de cargo · sustituida (con quién la sustituyó y de qué partido).

-- ── 1. Cédula ──
alter table public.aspirantes add column if not exists cedula text;
create index if not exists aspirantes_cedula_idx on public.aspirantes (cedula);
update public.aspirantes a
   set cedula = j.cedula_fmt, updated_at = now()
  from public.jce_juntas_2026 j
 where j.aspirante_id = a.id and a.cedula is distinct from j.cedula_fmt;

-- ── 2. Foto de mayo ──
create table if not exists public.jce_seleccion_mayo_2026 (
  aspirante_id  bigint primary key,
  municipio_id  integer,
  persona       text,
  partido_id    integer,
  cargo_mayo    text,
  marcado_el    timestamptz,
  guardado_en   timestamptz not null default now()
);
insert into public.jce_seleccion_mayo_2026 (aspirante_id, municipio_id, persona, partido_id, cargo_mayo, marcado_el)
select a.id, a.municipio_id, concat_ws(' ', a.nombres, a.apellido1, a.apellido2), a.partido_id,
       replace(replace(coalesce(a.cargo_aspira, a.cargo_electo), 'Segunda Vocal', 'Segundo Vocal'), 'Primera Vocal', 'Primer Vocal'),
       a.fecha_seleccion
  from public.aspirantes a
 where a.seleccionado and a.fecha_seleccion < '2026-06-01'
on conflict (aspirante_id) do nothing;
alter table public.jce_seleccion_mayo_2026 enable row level security;
drop policy if exists jsm_lee on public.jce_seleccion_mayo_2026;
create policy jsm_lee on public.jce_seleccion_mayo_2026 for select to authenticated using (true);
grant select on public.jce_seleccion_mayo_2026 to authenticated;

-- ── 3. Vista de la resolución ──
create or replace view public.vista_juntas_2026 as
select j.junta, j.municipio_jce, m.id as municipio_id, m.nombre as municipio, m.provincia_nombre as provincia, m.macroregion,
       j.orden, j.cargo, j.titular, j.cedula_fmt as cedula,
       coalesce(j.nombre_padron, j.nombre) as persona,
       j.aspirante_id, p.id as partido_id, p.siglas as partido, p.nombre as partido_nombre,
       a.cargo_aspira,
       case when j.aspirante_id is null then 'no está en la base'
            when j.match_tipo = 'nombre_completo' then 'nombre exacto'
            when j.match_tipo = 'manual' then 'revisado a mano'
            else 'nombre aproximado' end as emparejamiento,
       (s.aspirante_id is not null) as estaba_en_mayo,
       s.cargo_mayo,
       case when s.aspirante_id is null then null
            when s.cargo_mayo = j.cargo then 'se mantiene' else 'cambió de cargo' end as respecto_a_mayo
  from public.jce_juntas_2026 j
  left join public.municipios m on m.id = j.municipio_id
  left join public.aspirantes a on a.id = j.aspirante_id
  left join public.partidos p on p.id = j.partido_id
  left join public.jce_seleccion_mayo_2026 s on s.aspirante_id = j.aspirante_id;
grant select on public.vista_juntas_2026 to authenticated;

-- ── 4. Vista de cambios: cada persona de mayo frente a la resolución ──
create or replace view public.vista_cambios_mayo_2026 as
select s.aspirante_id, m.id as municipio_id, m.nombre as municipio, m.provincia_nombre as provincia,
       s.persona, pm.siglas as partido_mayo, s.cargo_mayo, s.marcado_el::date as marcado_el,
       case when jr.aspirante_id is not null and jr.cargo = s.cargo_mayo then 'se mantiene'
            when jr.aspirante_id is not null then 'cambió de cargo'
            else 'sustituida' end as situacion,
       jr.cargo as cargo_ahora,
       coalesce(jc.nombre_padron, jc.nombre) as quien_ocupa_su_cargo,
       pc.siglas as partido_de_quien_ocupa,
       (jc.aspirante_id is null) as ocupante_fuera_de_la_base
  from public.jce_seleccion_mayo_2026 s
  left join public.municipios m on m.id = s.municipio_id
  left join public.partidos pm on pm.id = s.partido_id
  left join public.jce_juntas_2026 jr on jr.aspirante_id = s.aspirante_id                    -- dónde quedó la persona
  left join public.jce_juntas_2026 jc on jc.municipio_id = s.municipio_id and jc.cargo = s.cargo_mayo   -- quién tiene hoy su cargo de mayo
  left join public.partidos pc on pc.id = jc.partido_id;
grant select on public.vista_cambios_mayo_2026 to authenticated;

-- Comprobación. Esperado: 1 fila; foto_mayo = 303, con_cedula alrededor de 1,409, y el desglose de situaciones.
select (select count(*) from public.jce_seleccion_mayo_2026) as foto_mayo,
       (select count(*) from public.aspirantes where cedula is not null) as con_cedula,
       (select count(*) from public.vista_cambios_mayo_2026 where situacion = 'se mantiene') as se_mantienen,
       (select count(*) from public.vista_cambios_mayo_2026 where situacion = 'cambió de cargo') as cambiaron_de_cargo,
       (select count(*) from public.vista_cambios_mayo_2026 where situacion = 'sustituida') as sustituidas;
