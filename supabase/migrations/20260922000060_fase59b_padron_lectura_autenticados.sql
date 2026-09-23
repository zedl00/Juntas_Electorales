-- fase59b_padron_lectura_autenticados.sql · Portal de Delegados 2028
-- Idempotente.
--
-- La fase 59 retiró todo acceso del cliente a public.jce_padron. La aplicación
-- Strategos (electoral/index.html) consulta el padrón directamente desde el
-- navegador, pero solo tras iniciar sesión con Supabase Auth. Se le devuelve
-- ÚNICAMENTE la lectura al rol authenticated. El rol anon sigue sin acceso.
--
-- Estado resultante:
--   anon          → nada
--   authenticated → select (sujeto a las políticas RLS de la tabla)
--   funciones security definer del portal → sin cambios
--
-- Paso siguiente previsto (fase 61): sustituir las lecturas directas de
-- Strategos por funciones definer con columnas acotadas y resumen agregado,
-- y volver a retirar este select.

revoke all on table public.jce_padron from anon, authenticated;
grant select on table public.jce_padron to authenticated;

-- Comprobación: debe devolver exactamente una fila: authenticated | SELECT
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'jce_padron'
  and grantee in ('anon','authenticated');
