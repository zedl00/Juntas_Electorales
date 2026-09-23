-- ================================================================
--  PORTAL DE DELEGADOS 2028 · FASE 24
--  FORMULARIOS FIRMADOS ESCANEADOS + SELLO DE INTEGRIDAD
-- ----------------------------------------------------------------
--  1. Recepción de los formularios físicos firmados: se escanean
--     desde el teléfono, se archivan y quedan asociados al
--     expediente, con su huella criptográfica.
--  2. Cadena de integridad: cada expediente sella al anterior con
--     SHA-256. Alterar un registro antiguo rompe la cadena y queda
--     en evidencia. No exige confiar en nadie: se verifica.
--
--  REQUISITO PREVIO: crear en Supabase → Storage un bucket PRIVADO
--  llamado exactamente  formularios
--
--  EJECUTAR COMPLETO, DE UNA SOLA VEZ.
-- ================================================================

set search_path = delegados, public;

create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------
-- 1. FORMULARIOS FIRMADOS
-- ----------------------------------------------------------------
create table if not exists delegados.formularios_firmados (
  id            bigint generated always as identity primary key,
  postulante_id bigint not null references delegados.postulantes_2028(id) on delete cascade,
  municipio_id  integer,
  tipo          text not null default 'individual'
                check (tipo in ('individual','general','validacion','soporte')),
  ruta          text not null,
  nombre_archivo text,
  tamano_bytes  bigint,
  hash_sha256   text,
  paginas       smallint default 1,
  estado        text not null default 'recibido'
                check (estado in ('recibido','verificado','observado')),
  nota          text,
  subido_por    uuid,
  subido_at     timestamptz not null default now(),
  revisado_por  uuid,
  revisado_at   timestamptz
);

create index if not exists ff_post_idx on delegados.formularios_firmados (postulante_id);
create index if not exists ff_mun_idx  on delegados.formularios_firmados (municipio_id, estado);

alter table delegados.formularios_firmados enable row level security;
grant select, insert, update, delete on delegados.formularios_firmados to authenticated;

-- Alcance territorial: se ve y se sube solo lo del propio territorio
drop policy if exists ff_select on delegados.formularios_firmados;
create policy ff_select on delegados.formularios_firmados
for select to authenticated using (
  delegados.portal_rol() in ('admin_sne','consulta_nacional')
  or exists (select 1 from delegados.postulantes_2028 p
              where p.id = postulante_id
                and (p.municipio_id = delegados.portal_mun()
                  or (delegados.portal_rol() = 'supervisor_provincial' and p.provincia_id = delegados.portal_prov())
                  or (delegados.portal_rol() = 'coordinador_regional'  and p.macroregion = delegados.portal_region())))
);

drop policy if exists ff_insert on delegados.formularios_firmados;
create policy ff_insert on delegados.formularios_firmados
for insert to authenticated with check (
  delegados.portal_rol() = 'admin_sne'
  or exists (select 1 from delegados.postulantes_2028 p
              where p.id = postulante_id and p.municipio_id = delegados.portal_mun())
);

drop policy if exists ff_update on delegados.formularios_firmados;
create policy ff_update on delegados.formularios_firmados
for update to authenticated using (delegados.portal_rol() = 'admin_sne')
with check (delegados.portal_rol() = 'admin_sne');

-- Registro del archivo subido (deja rastro en la bitácora)
create or replace function delegados.portal_formulario_registrar(
  p_postulante bigint, p_ruta text, p_hash text default null,
  p_tipo text default 'individual', p_nombre text default null,
  p_tamano bigint default null, p_paginas smallint default 1)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
declare v_mun integer; v_num text; v_id bigint;
begin
  select municipio_id, numero_formulario into v_mun, v_num
    from postulantes_2028 where id = p_postulante;
  if v_mun is null then raise exception 'Expediente no encontrado'; end if;

  insert into formularios_firmados (postulante_id, municipio_id, tipo, ruta, nombre_archivo,
                                    tamano_bytes, hash_sha256, paginas, subido_por)
  values (p_postulante, v_mun, coalesce(p_tipo,'individual'), p_ruta, p_nombre,
          p_tamano, p_hash, coalesce(p_paginas,1), auth.uid())
  returning id into v_id;

  perform portal_log('formulario_recibido', 'postulante', v_num,
                     jsonb_build_object('tipo', p_tipo, 'hash', p_hash, 'archivo', p_nombre));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

revoke all on function delegados.portal_formulario_registrar(bigint,text,text,text,text,bigint,smallint) from public, anon;
grant execute on function delegados.portal_formulario_registrar(bigint,text,text,text,text,bigint,smallint) to authenticated;

-- Marcar verificado / observado (Comisión)
create or replace function delegados.portal_formulario_estado(p_id bigint, p_estado text, p_nota text default null)
returns jsonb
language plpgsql volatile security definer set search_path = delegados, public as $$
begin
  if portal_rol() <> 'admin_sne' then
    raise exception 'Solo la Comisión puede verificar formularios';
  end if;
  update formularios_firmados
     set estado = p_estado, nota = p_nota, revisado_por = auth.uid(), revisado_at = now()
   where id = p_id;
  perform portal_log('formulario_' || p_estado, 'formulario', p_id::text, jsonb_build_object('nota', p_nota));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function delegados.portal_formulario_estado(bigint,text,text) from public, anon;
grant execute on function delegados.portal_formulario_estado(bigint,text,text) to authenticated;

-- ----------------------------------------------------------------
-- 2. SELLO DE INTEGRIDAD ENCADENADO
-- ----------------------------------------------------------------
alter table delegados.postulantes_2028 add column if not exists sello_hash text;
alter table delegados.postulantes_2028 add column if not exists sello_anterior text;
alter table delegados.postulantes_2028 add column if not exists sello_at timestamptz;

create or replace function delegados.trg_p28_sello() returns trigger
language plpgsql security definer set search_path = delegados, public, extensions as $$
declare v_prev text; v_base text;
begin
  select sello_hash into v_prev from postulantes_2028
   where sello_hash is not null order by sello_at desc nulls last limit 1;

  v_base := concat_ws('|', new.cedula, new.nombres, new.apellido1, coalesce(new.apellido2,''),
                      new.municipio_id::text, coalesce(new.id_colegio_padron::text,''),
                      new.cargo_postulado, new.numero_formulario,
                      coalesce(v_prev, 'GENESIS'));
  new.sello_anterior := v_prev;
  new.sello_hash := encode(extensions.digest(v_base, 'sha256'), 'hex');
  new.sello_at := now();
  return new;
end $$;

drop trigger if exists p28_sello on delegados.postulantes_2028;
create trigger p28_sello
before insert on delegados.postulantes_2028
for each row execute function delegados.trg_p28_sello();

-- Verificación de la cadena completa (la prueba en vivo)
create or replace function delegados.portal_verificar_cadena()
returns table (total bigint, integros bigint, alterados bigint, detalle jsonb)
language plpgsql stable security definer set search_path = delegados, public, extensions as $$
begin
  if portal_rol() not in ('admin_sne','consulta_nacional') then
    raise exception 'Solo la administración de la SNE puede verificar la cadena';
  end if;

  return query
  with calc as (
    select p.numero_formulario, p.sello_hash,
           encode(extensions.digest(
             concat_ws('|', p.cedula, p.nombres, p.apellido1, coalesce(p.apellido2,''),
                       p.municipio_id::text, coalesce(p.id_colegio_padron::text,''),
                       p.cargo_postulado, p.numero_formulario,
                       coalesce(p.sello_anterior,'GENESIS')), 'sha256'), 'hex') as recalculado
      from postulantes_2028 p
     where p.sello_hash is not null
  )
  select count(*)::bigint,
         count(*) filter (where sello_hash = recalculado)::bigint,
         count(*) filter (where sello_hash <> recalculado)::bigint,
         coalesce((select jsonb_agg(jsonb_build_object('formulario', numero_formulario))
                     from calc where sello_hash <> recalculado), '[]'::jsonb)
    from calc;
end $$;

revoke all on function delegados.portal_verificar_cadena() from public, anon;
grant execute on function delegados.portal_verificar_cadena() to authenticated;

-- ----------------------------------------------------------------
-- 3. COBERTURA DOCUMENTAL POR MUNICIPIO
-- ----------------------------------------------------------------
create or replace function delegados.portal_cobertura_documental()
returns table (municipio_id integer, postulantes bigint, con_formulario bigint, verificados bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
declare v_rol text := portal_rol();
begin
  if v_rol is null then raise exception 'Acceso no autorizado'; end if;
  if v_rol = 'consulta_nacional' then v_rol := 'admin_sne'; end if;

  return query
  select p.municipio_id,
         count(distinct p.id)::bigint,
         count(distinct f.postulante_id)::bigint,
         count(distinct f.postulante_id) filter (where f.estado = 'verificado')::bigint
    from postulantes_2028 p
    left join formularios_firmados f on f.postulante_id = p.id
   where p.estado not in ('rechazado','no_aprobado')
     and (v_rol = 'admin_sne'
       or (v_rol in ('presidente','secretario_general','enc_electoral') and p.municipio_id = portal_mun())
       or (v_rol = 'supervisor_provincial' and p.provincia_id = portal_prov())
       or (v_rol = 'coordinador_regional'  and p.macroregion = portal_region()))
   group by p.municipio_id;
end $$;

revoke all on function delegados.portal_cobertura_documental() from public, anon;
grant execute on function delegados.portal_cobertura_documental() to authenticated;

notify pgrst, 'reload schema';

-- ── VERIFICACIÓN ──
--   select * from delegados.portal_verificar_cadena();
--   Debe devolver alterados = 0. Para la demostración en vivo:
--     update delegados.postulantes_2028 set nombres = 'ALTERADO' where cedula = '...';
--     select * from delegados.portal_verificar_cadena();   → alterados = 1, con su folio
