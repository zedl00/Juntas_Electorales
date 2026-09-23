-- fase58_blindaje_public.sql · Portal de Delegados 2028
-- Idempotente: puede ejecutarse varias veces sin efecto adicional.
--
-- Contexto (auditoría 22 sep 2026): en el esquema public los roles anon y
-- authenticated tenían TODOS los privilegios (incluido truncate) sobre cada
-- tabla, y seis tablas no tenían RLS. El portal nunca lee ni escribe public
-- directamente: todo pasa por funciones security definer del esquema delegados,
-- que se ejecutan como su dueño y no dependen de estos privilegios.

-- 1. Catálogos de la Junta (jce_*): lectura permitida, escritura jamás desde el cliente.
do $$
declare t record;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public' and tablename like 'jce\_%'
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table public.%I from anon, authenticated',
      t.tablename);
  end loop;
end $$;

-- 2. Respaldos y tablas auxiliares sin RLS: se activa RLS y se retiran privilegios.
--    Sin política y sin privilegio quedan cerradas al cliente; el dueño sigue accediendo.
do $$
declare t text;
begin
  foreach t in array array[
    'delegados_fp_backup_2024',
    'delegados_fp_backup_abril2026',
    'delegados_fp_backup_sae2024',
    'municipios_pre_fix_20260508_032626',
    '_mapeo_municipio',
    '_mapeo_provincia'
  ] loop
    if exists (select 1 from pg_tables where schemaname = 'public' and tablename = t) then
      execute format('alter table public.%I enable row level security', t);
      execute format('revoke all on table public.%I from anon, authenticated', t);
    end if;
  end loop;
end $$;

-- 3. Bitácoras del portal: inmutables desde el cliente (solo lectura e inserción).
revoke update, delete, truncate on table delegados.eventos_sistema     from authenticated;
revoke update, delete, truncate on table delegados.postulantes_bitacora from authenticated;

-- 4. El cliente nunca borra postulantes ni usuarios: la baja es un cambio de estado.
--    Las funciones portal_* son security definer y no se ven afectadas.
--    Si alguna función NO definer llegara a fallar con «permission denied»,
--    revertir con: grant delete on table delegados.<tabla> to authenticated;
revoke delete on table delegados.postulantes_2028       from authenticated;
revoke delete on table delegados.usuarios_territoriales from authenticated;

-- 5. Comprobación: debe devolver cero filas.
select n.nspname as esquema, c.relname as tabla, g.grantee, g.privilege_type
from information_schema.role_table_grants g
join pg_class c on c.relname = g.table_name
join pg_namespace n on n.oid = c.relnamespace and n.nspname = g.table_schema
where g.table_schema = 'public' and g.table_name like 'jce\_%'
  and g.grantee in ('anon','authenticated') and g.privilege_type <> 'SELECT'
order by 2, 3;
