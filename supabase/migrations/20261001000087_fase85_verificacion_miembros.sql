-- fase85_verificacion_miembros.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Verificación de membresía de los postulantes con la Secretaría de Organización.
-- Circuito único, por API o manual: el portal arma LOTES de cédulas pendientes (200 por
-- defecto, parametrizable); la Secretaría devuelve cada cédula con su estado; el portal
-- lo guarda en el postulante y en una tabla de resultados, con bitácora de cada llamada.
--
-- Estados del postulante (miembro_estado):
--   pendiente     registrado, aún no enviado en ningún lote (interno)
--   enviado       salió en un lote, sin respuesta todavía (interno)
--   miembro       la Secretaría confirma que es miembro
--   no_miembro    existe en su padrón pero no es miembro
--   no_localizado la cédula no aparece en su padrón
--   en_revision   lo están revisando; vuelve a salir en un lote futuro
-- Decisión del 1 oct 2026: los estados solo se marcan y se reportan; no bloquean nada.

-- ── 1. Columnas en postulantes ──
alter table delegados.postulantes_2028 add column if not exists miembro_estado text not null default 'pendiente';
alter table delegados.postulantes_2028 add column if not exists miembro_lote integer;
alter table delegados.postulantes_2028 add column if not exists miembro_verificado_en timestamptz;
alter table delegados.postulantes_2028 add column if not exists miembro_nota text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'p28_miembro_estado_chk') then
    alter table delegados.postulantes_2028 add constraint p28_miembro_estado_chk
      check (miembro_estado in ('pendiente','enviado','miembro','no_miembro','no_localizado','en_revision'));
  end if;
end $$;
create index if not exists p28_miembro_estado_idx on delegados.postulantes_2028 (miembro_estado);

-- Solo la administración (desde el portal) o el rol de servicio (API) cambian la verificación
create or replace function delegados.trg_p28_miembro_protege() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null and coalesce(delegados.portal_rol(), '') <> 'admin_sne'
     and (new.miembro_estado, new.miembro_lote, new.miembro_verificado_en, new.miembro_nota)
         is distinct from (old.miembro_estado, old.miembro_lote, old.miembro_verificado_en, old.miembro_nota) then
    raise exception 'La verificación de miembro solo la cambia la Secretaría de Organización o la administración';
  end if;
  return new;
end $$;
drop trigger if exists zz_p28_miembro_protege on delegados.postulantes_2028;
create trigger zz_p28_miembro_protege before update on delegados.postulantes_2028
  for each row execute function delegados.trg_p28_miembro_protege();

-- ── 2. Tablas ──
create table if not exists delegados.config_verificacion (
  id boolean primary key default true check (id),
  lote_tamano integer not null default 200,
  lote_maximo integer not null default 500,
  actualizado_por text, actualizado_en timestamptz
);
insert into delegados.config_verificacion (id) values (true) on conflict do nothing;

create table if not exists delegados.api_clientes (
  id serial primary key,
  nombre text not null,
  clave_hash text not null unique,
  prefijo text not null,
  alcance text not null default 'verificacion',
  activo boolean not null default true,
  ip_permitidas text[],
  limite_lote integer,
  creado_en timestamptz not null default now(), creado_por text,
  ultimo_uso timestamptz,
  revocado_en timestamptz, revocado_por text
);
create table if not exists delegados.api_bitacora (
  id bigserial primary key,
  cliente_id integer references delegados.api_clientes(id),
  cliente text, endpoint text not null, ip text, agente text,
  n_recibidos integer not null default 0, n_aceptados integer not null default 0, n_rechazados integer not null default 0,
  resultado text not null, detalle jsonb,
  created_at timestamptz not null default now()
);
create index if not exists api_bitacora_created_idx on delegados.api_bitacora (created_at desc);
create table if not exists delegados.verificacion_lotes (
  id serial primary key,
  creado_en timestamptz not null default now(),
  via text not null check (via in ('api','manual')),
  cliente_id integer references delegados.api_clientes(id),
  creado_por text,
  cantidad integer not null default 0,
  respondidos integer not null default 0,
  ultima_respuesta timestamptz
);
create table if not exists delegados.verificacion_resultados (
  id bigserial primary key,
  lote_id integer references delegados.verificacion_lotes(id),
  cedula text not null,
  estado text not null check (estado in ('miembro','no_miembro','no_localizado','en_revision')),
  nota text,
  fuente text not null check (fuente in ('api','manual')),
  cliente_id integer, recibido_por text,
  recibido_en timestamptz not null default now()
);
create index if not exists verif_res_cedula_idx on delegados.verificacion_resultados (cedula);

alter table delegados.config_verificacion enable row level security;
alter table delegados.api_clientes enable row level security;
alter table delegados.api_bitacora enable row level security;
alter table delegados.verificacion_lotes enable row level security;
alter table delegados.verificacion_resultados enable row level security;
grant select on delegados.config_verificacion, delegados.api_clientes, delegados.api_bitacora,
                delegados.verificacion_lotes, delegados.verificacion_resultados to authenticated;
drop policy if exists cv_admin on delegados.config_verificacion;
create policy cv_admin on delegados.config_verificacion for select to authenticated using (delegados.portal_rol() = 'admin_sne');
drop policy if exists ac_admin on delegados.api_clientes;
create policy ac_admin on delegados.api_clientes for select to authenticated using (delegados.portal_rol() = 'admin_sne');
drop policy if exists ab_admin on delegados.api_bitacora;
create policy ab_admin on delegados.api_bitacora for select to authenticated using (delegados.portal_rol() = 'admin_sne');
drop policy if exists vl_admin on delegados.verificacion_lotes;
create policy vl_admin on delegados.verificacion_lotes for select to authenticated using (delegados.portal_rol() = 'admin_sne');
drop policy if exists vr_admin on delegados.verificacion_resultados;
create policy vr_admin on delegados.verificacion_resultados for select to authenticated using (delegados.portal_rol() = 'admin_sne');

-- ── 3. Utilidades ──
create or replace function delegados._cedula_valida(p text) returns boolean
language plpgsql immutable as $$
declare c text := regexp_replace(coalesce(p,''), '\D', '', 'g'); s integer := 0; v integer; i integer;
begin
  if length(c) <> 11 then return false; end if;
  for i in 1..10 loop
    v := substr(c, i, 1)::integer * (case when i % 2 = 1 then 1 else 2 end);
    if v > 9 then v := v - 9; end if;
    s := s + v;
  end loop;
  return ((10 - s % 10) % 10) = substr(c, 11, 1)::integer;
end $$;

create or replace function delegados._verif_es_admin_o_servicio() returns boolean
language sql stable as $$ select auth.uid() is null or coalesce(delegados.portal_rol(), '') = 'admin_sne' $$;

-- ── 4. Clientes del API ──
create or replace function delegados.portal_api_cliente_crear(p_nombre text, p_limite integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public, extensions as $$
declare v_clave text; v_nom text; v_id integer;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Nombre del consumidor demasiado corto'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  v_clave := 'fp_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into api_clientes (nombre, clave_hash, prefijo, limite_lote, creado_por)
  values (btrim(p_nombre), encode(extensions.digest(v_clave, 'sha256'), 'hex'), left(v_clave, 10), p_limite, v_nom)
  returning id into v_id;
  perform portal_log('api_cliente_alta', 'api', v_id::text, jsonb_build_object('nombre', btrim(p_nombre)));
  return jsonb_build_object('id', v_id, 'nombre', btrim(p_nombre), 'clave', v_clave);
end $$;

create or replace function delegados.portal_api_cliente_revocar(p_id integer)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  update api_clientes set activo = false, revocado_en = now(), revocado_por = v_nom where id = p_id and activo;
  perform portal_log('api_cliente_revocado', 'api', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function delegados.portal_api_clientes()
returns table(id integer, nombre text, prefijo text, activo boolean, limite_lote integer, creado_en timestamptz,
              creado_por text, ultimo_uso timestamptz, revocado_en timestamptz)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query select c.id, c.nombre, c.prefijo, c.activo, c.limite_lote, c.creado_en, c.creado_por, c.ultimo_uso, c.revocado_en
    from api_clientes c order by c.activo desc, c.creado_en desc;
end $$;

-- Solo el rol de servicio (función «verificacion»): valida la clave y devuelve el cliente
create or replace function delegados.portal_api_cliente_validar(p_clave text)
returns jsonb language plpgsql security definer set search_path = delegados, public, extensions as $$
declare c record;
begin
  if auth.uid() is not null then raise exception 'Acceso no autorizado'; end if;
  select * into c from api_clientes where clave_hash = encode(extensions.digest(coalesce(p_clave,''), 'sha256'), 'hex') and activo;
  if c.id is null then return null; end if;
  update api_clientes set ultimo_uso = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'nombre', c.nombre, 'limite_lote', c.limite_lote, 'ip_permitidas', to_jsonb(coalesce(c.ip_permitidas, '{}'::text[])));
end $$;

create or replace function delegados.portal_api_log(p_cliente_id integer, p_cliente text, p_endpoint text, p_ip text, p_agente text,
  p_recibidos integer, p_aceptados integer, p_rechazados integer, p_resultado text, p_detalle jsonb default null)
returns void language sql security definer set search_path = delegados, public as $$
  insert into delegados.api_bitacora (cliente_id, cliente, endpoint, ip, agente, n_recibidos, n_aceptados, n_rechazados, resultado, detalle)
  values (p_cliente_id, p_cliente, p_endpoint, p_ip, left(p_agente, 200), coalesce(p_recibidos,0), coalesce(p_aceptados,0), coalesce(p_rechazados,0), p_resultado, p_detalle)
$$;

create or replace function delegados.portal_api_bitacora(p_limit integer default 100)
returns table(id bigint, cliente text, endpoint text, ip text, n_recibidos integer, n_aceptados integer, n_rechazados integer, resultado text, detalle jsonb, created_at timestamptz)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query select b.id, coalesce(b.cliente, '—'), b.endpoint, b.ip, b.n_recibidos, b.n_aceptados, b.n_rechazados, b.resultado, b.detalle, b.created_at
    from api_bitacora b order by b.created_at desc limit least(coalesce(p_limit,100), 500);
end $$;

-- ── 5. Lotes ──
create or replace function delegados.portal_verif_lote_crear(p_via text, p_limite integer default null, p_cliente_id integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare cfg record; v_lim integer; v_id integer; v_por text; v_ids bigint[]; v_regs jsonb;
begin
  if not delegados._verif_es_admin_o_servicio() then raise exception 'Solo la administración de la SNE'; end if;
  if p_via not in ('api','manual') then raise exception 'Vía no válida'; end if;
  select * into cfg from config_verificacion where id;
  v_lim := least(greatest(coalesce(p_limite, cfg.lote_tamano), 1), cfg.lote_maximo);
  if p_via = 'manual' then select nombre into v_por from usuarios_territoriales where id = auth.uid();
  else select nombre into v_por from api_clientes where id = p_cliente_id; end if;

  select array_agg(id) into v_ids from (
    select p.id from postulantes_2028 p
     where p.miembro_estado in ('pendiente','en_revision')
       and p.estado not in ('rechazado','no_aprobado')
     order by p.created_at
     limit v_lim
     for update skip locked) x;
  if v_ids is null or array_length(v_ids, 1) is null then
    return jsonb_build_object('lote', null, 'cantidad', 0, 'registros', '[]'::jsonb);
  end if;

  insert into verificacion_lotes (via, cliente_id, creado_por, cantidad)
  values (p_via, p_cliente_id, v_por, array_length(v_ids, 1)) returning id into v_id;
  update postulantes_2028 set miembro_estado = 'enviado', miembro_lote = v_id where id = any(v_ids);
  select jsonb_agg(jsonb_build_object('cedula', regexp_replace(p.cedula, '\D', '', 'g')) order by p.created_at)
    into v_regs from postulantes_2028 p where p.id = any(v_ids);
  perform portal_log('verif_lote', 'lote', v_id::text, jsonb_build_object('via', p_via, 'cantidad', array_length(v_ids,1), 'por', v_por));
  return jsonb_build_object('lote', v_id, 'creado_en', now(), 'cantidad', array_length(v_ids, 1), 'registros', v_regs);
end $$;

create or replace function delegados.portal_verif_lote_obtener(p_lote integer)
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare l record; v_regs jsonb;
begin
  if not delegados._verif_es_admin_o_servicio() then raise exception 'Solo la administración de la SNE'; end if;
  select * into l from verificacion_lotes where id = p_lote;
  if l.id is null then return null; end if;
  select jsonb_agg(jsonb_build_object('cedula', regexp_replace(p.cedula, '\D', '', 'g'), 'estado', p.miembro_estado) order by p.created_at)
    into v_regs from postulantes_2028 p where p.miembro_lote = p_lote;
  return jsonb_build_object('lote', l.id, 'creado_en', l.creado_en, 'via', l.via, 'cantidad', l.cantidad,
                            'respondidos', l.respondidos, 'registros', coalesce(v_regs, '[]'::jsonb));
end $$;

-- ── 6. Resultados: cada cédula con su estado ──
create or replace function delegados.portal_verif_resultados(p_items jsonb, p_fuente text, p_cliente_id integer default null, p_lote integer default null)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare it jsonb; v_ced text; v_est text; v_nota text; p record; v_por text;
        v_ok integer := 0; v_rech jsonb := '[]'::jsonb; v_lotes integer[] := '{}';
begin
  if not delegados._verif_es_admin_o_servicio() then raise exception 'Solo la administración de la SNE'; end if;
  if p_fuente not in ('api','manual') then raise exception 'Fuente no válida'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'Se esperaba una lista de resultados'; end if;
  if jsonb_array_length(p_items) > 1000 then raise exception 'Máximo 1000 resultados por llamada'; end if;
  if p_fuente = 'manual' then select nombre into v_por from usuarios_territoriales where id = auth.uid();
  else select nombre into v_por from api_clientes where id = p_cliente_id; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    v_ced := regexp_replace(coalesce(it->>'cedula',''), '\D', '', 'g');
    v_est := lower(btrim(coalesce(it->>'estado','')));
    v_nota := left(it->>'nota', 300);
    if not delegados._cedula_valida(v_ced) then
      v_rech := v_rech || jsonb_build_object('cedula', coalesce(it->>'cedula',''), 'motivo', 'cédula inválida'); continue;
    end if;
    if v_est not in ('miembro','no_miembro','no_localizado','en_revision') then
      v_rech := v_rech || jsonb_build_object('cedula', v_ced, 'motivo', 'estado no permitido: ' || coalesce(it->>'estado','')); continue;
    end if;
    select id, miembro_estado, miembro_lote into p from postulantes_2028 where regexp_replace(cedula, '\D', '', 'g') = v_ced limit 1;
    if p.id is null then
      v_rech := v_rech || jsonb_build_object('cedula', v_ced, 'motivo', 'no es un postulante registrado'); continue;
    end if;
    if p.miembro_estado = 'pendiente' then
      v_rech := v_rech || jsonb_build_object('cedula', v_ced, 'motivo', 'no ha sido enviada en ningún lote'); continue;
    end if;
    insert into verificacion_resultados (lote_id, cedula, estado, nota, fuente, cliente_id, recibido_por)
    values (coalesce(p_lote, p.miembro_lote), v_ced, v_est, v_nota, p_fuente, p_cliente_id, v_por);
    update postulantes_2028 set miembro_estado = v_est, miembro_verificado_en = now(), miembro_nota = v_nota where id = p.id;
    v_ok := v_ok + 1;
    if coalesce(p_lote, p.miembro_lote) is not null and not (coalesce(p_lote, p.miembro_lote) = any(v_lotes)) then
      v_lotes := v_lotes || coalesce(p_lote, p.miembro_lote);
    end if;
  end loop;

  update verificacion_lotes l
     set respondidos = (select count(distinct r.cedula) from verificacion_resultados r where r.lote_id = l.id),
         ultima_respuesta = now()
   where l.id = any(v_lotes);
  perform portal_log('verif_resultados', 'lote', array_to_string(v_lotes, ','), jsonb_build_object('fuente', p_fuente, 'aceptados', v_ok, 'rechazados', jsonb_array_length(v_rech), 'por', v_por));
  return jsonb_build_object('aceptados', v_ok, 'rechazados', v_rech, 'lotes', to_jsonb(v_lotes));
end $$;

-- ── 7. Lectura para Gestión ──
create or replace function delegados.portal_verif_resumen()
returns jsonb language plpgsql stable security definer set search_path = delegados, public as $$
declare v jsonb;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  select jsonb_build_object(
    'pendiente',     count(*) filter (where miembro_estado = 'pendiente'),
    'enviado',       count(*) filter (where miembro_estado = 'enviado'),
    'miembro',       count(*) filter (where miembro_estado = 'miembro'),
    'no_miembro',    count(*) filter (where miembro_estado = 'no_miembro'),
    'no_localizado', count(*) filter (where miembro_estado = 'no_localizado'),
    'en_revision',   count(*) filter (where miembro_estado = 'en_revision'),
    'total',         count(*),
    'lotes',         (select count(*) from verificacion_lotes),
    'ultimo_lote',   (select max(creado_en) from verificacion_lotes),
    'ultima_respuesta', (select max(recibido_en) from verificacion_resultados),
    'config',        (select jsonb_build_object('lote_tamano', lote_tamano, 'lote_maximo', lote_maximo) from config_verificacion where id)
  ) into v from postulantes_2028 where estado not in ('rechazado','no_aprobado');
  return v;
end $$;

create or replace function delegados.portal_verif_lotes(p_limit integer default 50)
returns table(id integer, creado_en timestamptz, via text, cliente text, creado_por text, cantidad integer, respondidos integer, ultima_respuesta timestamptz,
              miembro bigint, no_miembro bigint, no_localizado bigint, en_revision bigint, sin_respuesta bigint)
language plpgsql stable security definer set search_path = delegados, public as $$
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  return query
  select l.id, l.creado_en, l.via, c.nombre, l.creado_por, l.cantidad, l.respondidos, l.ultima_respuesta,
         count(p.id) filter (where p.miembro_estado = 'miembro'),
         count(p.id) filter (where p.miembro_estado = 'no_miembro'),
         count(p.id) filter (where p.miembro_estado = 'no_localizado'),
         count(p.id) filter (where p.miembro_estado = 'en_revision'),
         count(p.id) filter (where p.miembro_estado = 'enviado')
    from verificacion_lotes l
    left join api_clientes c on c.id = l.cliente_id
    left join postulantes_2028 p on p.miembro_lote = l.id
   group by l.id, c.nombre
   order by l.id desc limit least(coalesce(p_limit,50), 500);
end $$;

create or replace function delegados.portal_verif_config_set(p_lote integer, p_maximo integer)
returns jsonb language plpgsql security definer set search_path = delegados, public as $$
declare v_nom text;
begin
  if delegados.portal_rol() <> 'admin_sne' then raise exception 'Solo la administración de la SNE'; end if;
  if coalesce(p_lote,0) < 1 or coalesce(p_maximo,0) < p_lote then raise exception 'Tamaño de lote no válido'; end if;
  select nombre into v_nom from usuarios_territoriales where id = auth.uid();
  update config_verificacion set lote_tamano = p_lote, lote_maximo = p_maximo, actualizado_por = v_nom, actualizado_en = now() where id;
  perform portal_log('config_verificacion', 'configuracion', null, jsonb_build_object('lote_tamano', p_lote, 'lote_maximo', p_maximo));
  return jsonb_build_object('ok', true);
end $$;

-- ── 8. Permisos ──
revoke all on function delegados.portal_api_cliente_validar(text) from public, anon, authenticated;
grant execute on function delegados.portal_api_cliente_validar(text) to service_role;
revoke all on function delegados.portal_api_log(integer, text, text, text, text, integer, integer, integer, text, jsonb) from public, anon, authenticated;
grant execute on function delegados.portal_api_log(integer, text, text, text, text, integer, integer, integer, text, jsonb) to service_role;
revoke all on function delegados.portal_verif_lote_crear(text, integer, integer) from public, anon;
grant execute on function delegados.portal_verif_lote_crear(text, integer, integer) to authenticated, service_role;
revoke all on function delegados.portal_verif_lote_obtener(integer) from public, anon;
grant execute on function delegados.portal_verif_lote_obtener(integer) to authenticated, service_role;
revoke all on function delegados.portal_verif_resultados(jsonb, text, integer, integer) from public, anon;
grant execute on function delegados.portal_verif_resultados(jsonb, text, integer, integer) to authenticated, service_role;
revoke all on function delegados.portal_api_cliente_crear(text, integer) from public, anon;
grant execute on function delegados.portal_api_cliente_crear(text, integer) to authenticated;
revoke all on function delegados.portal_api_cliente_revocar(integer) from public, anon;
grant execute on function delegados.portal_api_cliente_revocar(integer) to authenticated;
revoke all on function delegados.portal_api_clientes() from public, anon;
grant execute on function delegados.portal_api_clientes() to authenticated;
revoke all on function delegados.portal_api_bitacora(integer) from public, anon;
grant execute on function delegados.portal_api_bitacora(integer) to authenticated;
revoke all on function delegados.portal_verif_resumen() from public, anon;
grant execute on function delegados.portal_verif_resumen() to authenticated;
revoke all on function delegados.portal_verif_lotes(integer) from public, anon;
grant execute on function delegados.portal_verif_lotes(integer) to authenticated;
revoke all on function delegados.portal_verif_config_set(integer, integer) from public, anon;
grant execute on function delegados.portal_verif_config_set(integer, integer) to authenticated;

notify pgrst, 'reload schema';

-- Comprobación (sin sesión). Esperado: 1 fila con columna = true, tablas = 5, funciones = 12 y cedula_ok = true.
select exists (select 1 from information_schema.columns where table_schema = 'delegados' and table_name = 'postulantes_2028' and column_name = 'miembro_estado') as columna,
       (select count(*) from information_schema.tables where table_schema = 'delegados' and table_name in ('config_verificacion','api_clientes','api_bitacora','verificacion_lotes','verificacion_resultados')) as tablas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'delegados' and p.proname in
          ('portal_api_cliente_crear','portal_api_cliente_revocar','portal_api_clientes','portal_api_cliente_validar','portal_api_log','portal_api_bitacora',
           'portal_verif_lote_crear','portal_verif_lote_obtener','portal_verif_resultados','portal_verif_resumen','portal_verif_lotes','portal_verif_config_set')) as funciones,
       delegados._cedula_valida('001-0209399-4') as cedula_ok;
