-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 12
--  EXPERIENCIA 2020 / 2024 · CANDIDATO FIRME
-- ----------------------------------------------------------------
--  Ajuste puntual del expediente del postulante:
--   · experiencia_2020 / experiencia_2024 como marcas independientes
--     (antes 2024 se deducía sola del histórico; ahora ambas se
--      certifican en el formulario).
--   · candidato_firme: el formulario fue firmado por los tres
--     ejecutivos del territorio ANTES de la preselección.
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ. Idempotente.
--  No toca ninguna otra funcionalidad.
-- ================================================================

set search_path = delegados, public;

alter table delegados.postulantes_2028
  add column if not exists experiencia_2020 boolean not null default false;

alter table delegados.postulantes_2028
  add column if not exists candidato_firme boolean not null default false;

alter table delegados.postulantes_2028
  add column if not exists firme_fecha date;

comment on column delegados.postulantes_2028.experiencia_2020 is
  'Fue delegado(a), suplente u observador(a) en el proceso electoral 2020.';
comment on column delegados.postulantes_2028.experiencia_2024 is
  'Fue delegado(a), suplente u observador(a) en el proceso electoral 2024.';
comment on column delegados.postulantes_2028.candidato_firme is
  'Candidato firme: formulario firmado por Presidente(a), Secretario(a) General y Encargado(a) Electoral antes de la preselección.';

create index if not exists p28_firme_idx on delegados.postulantes_2028 (candidato_firme);

-- La fecha de firmeza se sella sola al marcar la casilla, y se limpia al desmarcar
create or replace function delegados.trg_p28_firme() returns trigger
language plpgsql security definer set search_path = delegados, public as $$
begin
  if new.candidato_firme and (tg_op = 'INSERT' or not coalesce(old.candidato_firme, false)) then
    new.firme_fecha := coalesce(new.firme_fecha, current_date);
  elsif not new.candidato_firme then
    new.firme_fecha := null;
  end if;
  return new;
end $$;

drop trigger if exists p28_firme on delegados.postulantes_2028;
create trigger p28_firme
before insert or update of candidato_firme on delegados.postulantes_2028
for each row execute function delegados.trg_p28_firme();

-- El KPI nacional/territorial suma las tres marcas nuevas
create or replace function delegados.portal_kpi(p_municipio integer default null)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_rol text := portal_rol();
  v jsonb;
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  with alcance as (
    select v2.municipio_id, v2.meta, v2.colegios
      from portal_metas_municipio v2
     where (v2.estatus is null or v2.estatus <> 'I')
       and (p_municipio is null or v2.municipio_id = p_municipio)
       and (
         v_rol = 'admin_sne'
         or (v_rol in ('presidente','secretario_general','enc_electoral') and v2.municipio_id = portal_mun())
         or (v_rol = 'supervisor_provincial' and v2.provincia_id = portal_prov())
         or (v_rol = 'coordinador_regional'  and v2.macroregion = portal_region())
       )
  ),
  post as (
    select p.* from postulantes_2028 p
      join alcance a on a.municipio_id = p.municipio_id
     where (portal_distrito() is null or p.jce_id = portal_distrito())
  ),
  tot as (select coalesce(sum(meta),0) meta, coalesce(sum(colegios),0) col from alcance),
  cub as (
    select count(*) n from (
      select id_colegio_padron from post
       where estado not in ('rechazado','no_aprobado') and id_colegio_padron is not null
       group by id_colegio_padron having count(*) >= 3
    ) x
  )
  select jsonb_build_object(
    'meta',               (select meta from tot),
    'colegios',           (select col from tot),
    'colegios_cubiertos', (select n from cub),
    'total',              (select count(*) from post where estado not in ('rechazado','no_aprobado')),
    'hoy',                (select count(*) from post where created_at::date = current_date),
    'semana',             (select count(*) from post where created_at >= now() - interval '7 days'),
    'con_experiencia',    (select count(*) from post where experiencia_2024 or experiencia_2020),
    'exp_2020',           (select count(*) from post where experiencia_2020),
    'exp_2024',           (select count(*) from post where experiencia_2024),
    'firmes',             (select count(*) from post where candidato_firme),
    'por_estado',         (select jsonb_object_agg(estado, n) from (select estado, count(*) n from post group by estado) e),
    'por_cargo',          (select jsonb_object_agg(cargo_postulado, n) from (select cargo_postulado, count(*) n from post group by cargo_postulado) c)
  ) into v;

  return v;
end $$;

revoke all on function delegados.portal_kpi(integer) from public, anon;
grant execute on function delegados.portal_kpi(integer) to authenticated;

-- La búsqueda por cédula ahora informa ambos años, para precargar las casillas
create or replace function delegados.portal_experiencia_previa(p_ced text) returns jsonb
language plpgsql stable security definer set search_path = delegados, public as $$
declare
  v_ced text := regexp_replace(coalesce(p_ced,''), '\D', '', 'g');
  v20 boolean := false; v24 boolean := false; v_det text := null;
begin
  if portal_rol() is null then raise exception 'Acceso no autorizado'; end if;
  begin
    select bool_or(coalesce(h.anio, h.ano, 2024) = 2020),
           bool_or(coalesce(h.anio, h.ano, 2024) = 2024),
           string_agg(distinct coalesce(h.cargo, h.funcion, ''), ' · ')
      into v20, v24, v_det
      from historial_delegado h
     where regexp_replace(coalesce(h.cedula,''), '\D', '', 'g') = v_ced;
  exception when others then
    v20 := false; v24 := false; v_det := null;
  end;
  return jsonb_build_object('exp_2020', coalesce(v20,false),
                            'exp_2024', coalesce(v24,false),
                            'detalle', nullif(trim(coalesce(v_det,'')), ''));
end $$;

revoke all on function delegados.portal_experiencia_previa(text) from public, anon;
grant execute on function delegados.portal_experiencia_previa(text) to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--  select column_name from information_schema.columns
--   where table_schema='delegados' and table_name='postulantes_2028'
--     and column_name in ('experiencia_2020','experiencia_2024','candidato_firme','firme_fecha');
