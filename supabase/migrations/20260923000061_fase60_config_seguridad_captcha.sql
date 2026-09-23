-- fase60_config_seguridad_captcha.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Interruptor del captcha (Cloudflare Turnstile) manejado por la administración
-- desde Gestión → Usuarios → Seguridad del acceso, sin recompilar ni tocar .env.
--
-- IMPORTANTE: este interruptor controla si la pantalla de acceso MUESTRA el reto
-- y envía el token. La EXIGENCIA del token la aplica Supabase Auth
-- (Authentication → Attack Protection → Captcha). Los dos deben coincidir:
--   portal ON  + Supabase ON  → protegido
--   portal OFF + Supabase OFF → sin captcha
--   portal OFF + Supabase ON  → nadie puede entrar (el portal avisa con mensaje claro)
--   portal ON  + Supabase OFF → el reto se muestra pero no se verifica

create table if not exists delegados.config_seguridad (
  id               boolean primary key default true check (id),
  captcha_activo   boolean not null default false,
  captcha_site_key text,
  actualizado_por  text,
  actualizado_en   timestamptz default now()
);
insert into delegados.config_seguridad (id) values (true) on conflict do nothing;

alter table delegados.config_seguridad enable row level security;
drop policy if exists cs_lee on delegados.config_seguridad;
create policy cs_lee on delegados.config_seguridad for select to authenticated using (true);
-- La escritura solo pasa por la función de abajo
revoke insert, update, delete, truncate on table delegados.config_seguridad from authenticated;

-- Guardar (solo administración)
create or replace function delegados.portal_config_seguridad_set(p_captcha boolean, p_site_key text)
returns json language plpgsql security definer set search_path = delegados, public as $$
declare v_nombre text;
begin
  if delegados.portal_rol() <> 'admin_sne' then
    raise exception 'Solo la administración puede cambiar la seguridad del acceso';
  end if;
  if p_captcha and coalesce(trim(p_site_key), '') = '' then
    raise exception 'Para activar el captcha hace falta la Site Key de Turnstile';
  end if;
  select nombre into v_nombre from delegados.usuarios_territoriales where id = auth.uid();
  update delegados.config_seguridad
     set captcha_activo   = p_captcha,
         captcha_site_key = nullif(trim(p_site_key), ''),
         actualizado_por  = v_nombre,
         actualizado_en   = now()
   where id;
  return json_build_object('ok', true);
end $$;
revoke execute on function delegados.portal_config_seguridad_set(boolean, text) from public;
grant  execute on function delegados.portal_config_seguridad_set(boolean, text) to authenticated;

-- Lectura pública: la pantalla de acceso la consulta sin sesión.
-- Vive en public porque el rol anon no tiene uso del esquema delegados, y así debe seguir.
-- La Site Key no es secreta: viaja en la página de todos modos.
create or replace function public.portal_config_publica()
returns json language sql stable security definer set search_path = delegados, public as $$
  select json_build_object(
    'captcha_activo',   c.captcha_activo and c.captcha_site_key is not null,
    'captcha_site_key', case when c.captcha_activo then c.captcha_site_key end)
  from delegados.config_seguridad c where c.id limit 1;
$$;
revoke execute on function public.portal_config_publica() from public;
grant  execute on function public.portal_config_publica() to anon, authenticated;

-- Comprobación: debe devolver {"captcha_activo": false, "captcha_site_key": null}
select public.portal_config_publica();
