-- fase59_padron_solo_funciones.sql · Portal de Delegados 2028
-- Idempotente.
--
-- El padrón electoral (public.jce_padron) contiene cédula, nombres, sexo,
-- fecha de nacimiento y colegio de millones de personas. Nadie debe poder
-- consultarlo con la clave anónima ni con una sesión: solo las funciones
-- security definer del portal (portal_buscar_cedula, portal_evaluar_traslado,
-- etc.), que se ejecutan como su dueño.
--
-- ANTES DE APLICAR: confirmar que ninguna otra aplicación del mismo proyecto
-- de Supabase (esquema public: strategos_*, mun_*, incidencias…) consulta
-- jce_padron directamente desde el navegador. Si alguna lo hace, dejará de
-- funcionar y habrá que darle su propia función definer.

revoke all on table public.jce_padron from anon, authenticated;

-- Comprobación: debe devolver cero filas.
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'jce_padron'
  and grantee in ('anon','authenticated');
