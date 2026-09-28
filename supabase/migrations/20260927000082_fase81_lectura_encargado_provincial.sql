-- fase81_lectura_encargado_provincial.sql · Portal de Delegados 2028
-- Idempotente.
--
-- Hallazgo del 27 sep con el usuario 01200549093 (encargado electoral con
-- provincia y sin municipio): el tablero muestra los totales de su provincia
-- (las funciones de KPI usan portal_ve_municipio, que entiende «provincia sin
-- municipio»), pero la lista de Postulantes sale vacía, porque la política de
-- lectura de la tabla solo entiende «municipio» para ese rol.
--
-- Esta fase alinea la LECTURA con lo que ya muestran los tableros: un
-- presidente, secretario general o encargado electoral sin municipio y con
-- provincia lee los expedientes y formularios de su provincia. No cambia nada
-- de registro, edición ni carga de formularios (decisión del 27 sep: el
-- registro por municipio para encargados provinciales queda para después).

-- ── Expedientes ──
drop policy if exists p28_select on delegados.postulantes_2028;
create policy p28_select on delegados.postulantes_2028
for select to authenticated using (
  delegados.portal_rol() in ('admin_sne','consulta_nacional')
  or (delegados.portal_mun() is not null and municipio_id = delegados.portal_mun()
      and (delegados.portal_distrito() is null or jce_id = delegados.portal_distrito()))
  or (delegados.portal_rol() = 'supervisor_provincial' and provincia_id = delegados.portal_prov())
  or (delegados.portal_rol() = 'coordinador_regional'  and macroregion = delegados.portal_region())
  -- nivel provincial sin municipio (mismo criterio que portal_ve_municipio)
  or (delegados.portal_mun() is null and delegados.portal_prov() is not null
      and delegados.portal_rol() in ('presidente','secretario_general','enc_electoral')
      and provincia_id = delegados.portal_prov())
);

-- ── Formularios firmados (misma lectura que los expedientes) ──
drop policy if exists ff_select on delegados.formularios_firmados;
create policy ff_select on delegados.formularios_firmados
for select to authenticated using (
  delegados.portal_rol() in ('admin_sne','consulta_nacional')
  or exists (
    select 1 from delegados.postulantes_2028 p
     where p.id = formularios_firmados.postulante_id
       and (p.municipio_id = delegados.portal_mun()
            or (delegados.portal_rol() = 'supervisor_provincial' and p.provincia_id = delegados.portal_prov())
            or (delegados.portal_rol() = 'coordinador_regional'  and p.macroregion = delegados.portal_region())
            or (delegados.portal_mun() is null and delegados.portal_prov() is not null
                and delegados.portal_rol() in ('presidente','secretario_general','enc_electoral')
                and p.provincia_id = delegados.portal_prov()))
  )
);

-- Comprobación (sin sesión). Esperado: 1 fila con politicas = 2 y con_provincia = true.
select count(*) as politicas,
       bool_and(qual like '%portal_mun() IS NULL%' and qual like '%enc_electoral%') as con_provincia
  from pg_policies
 where schemaname = 'delegados' and policyname in ('p28_select', 'ff_select');
