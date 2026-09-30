-- fase83b_cruce_pasadas_y_manual.sql · Registro de lo ejecutado a mano el 30 sep 2026 en el cruce
-- de la Resolución JCE 08-2026. Idempotente: se puede volver a correr sin efecto si ya se aplicó.

-- 1. Once juntas cuyo nombre en la resolución no coincidía con el de public.municipios
update public.jce_juntas_2026 j set municipio_id = v.mun
  from (values (3,10),(8,18),(26,1),(33,25),(48,27),(89,41),(91,22),(108,37),(122,65),(129,24),(155,155)) as v(junta, mun)
 where j.junta = v.junta and j.municipio_id is null;

-- 2. Pasada por apellido leído + primer nombre (recoge la ñ mal guardada en el padrón)
update public.jce_juntas_2026 j set aspirante_id = a.id, partido_id = a.partido_id, match_tipo = 'apellido_primer_nombre'
  from public.aspirantes a
 where j.aspirante_id is null and a.municipio_id = j.municipio_id and a.activo
   and not exists (select 1 from public.jce_juntas_2026 x where x.aspirante_id = a.id)
   and public._norm_txt(a.apellido1) = any (string_to_array(public._norm_txt(j.nombre), ' '))
   and split_part(public._norm_txt(a.nombres), ' ', 1) = split_part(public._norm_txt(j.nombre), ' ', 1);

-- 3. Pasada aproximada: tres o más palabras significativas en común, mismo municipio
update public.jce_juntas_2026 j set aspirante_id = a.id, partido_id = a.partido_id, match_tipo = 'aproximado'
  from public.aspirantes a
 where j.aspirante_id is null and a.municipio_id = j.municipio_id and a.activo
   and not exists (select 1 from public.jce_juntas_2026 x where x.aspirante_id = a.id)
   and (select count(*) from (select unnest(string_to_array(public._norm_txt(concat_ws(' ', a.nombres, a.apellido1, a.apellido2)), ' '))
                              intersect select unnest(string_to_array(public._norm_txt(j.nombre), ' '))) t
         where t.unnest not in ('DE','LA','DEL','LOS','LAS','Y','E','')) >= 3;

-- 4. Emparejamientos manuales revisados uno a uno (16)
update public.jce_juntas_2026 j set aspirante_id = a.id, partido_id = a.partido_id, match_tipo = 'manual'
  from (values (10,'Primer Suplente Segundo Vocal',3316),(10,'Segundo Suplente Segundo Vocal',3311),(21,'Segundo Suplente Segundo Vocal',1649),
               (22,'Segundo Suplente',3098),(22,'Primer Suplente Segundo Vocal',3117),(30,'Segundo Vocal',435),(32,'Segundo Suplente Primer Vocal',1276),
               (110,'Segundo Suplente Primer Vocal',3185),(112,'Primer Suplente Primer Vocal',1031),(117,'Segundo Suplente Primer Vocal',820),
               (129,'Primer Suplente Primer Vocal',8328),(137,'Segundo Suplente Tercer Vocal',3588),(156,'Primer Suplente Segundo Vocal',2612),
               (21,'Segundo Vocal',1654),(29,'Primer Vocal',1759),(38,'Segundo Vocal',1416)) as v(junta, cargo, asp)
  join public.aspirantes a on a.id = v.asp
 where j.junta = v.junta and j.cargo = v.cargo and j.aspirante_id is null;

-- Comprobación. Esperado: 1 fila; con_aspirante alrededor de 1,409 (1,476 menos los que no están en la base).
select count(*) as cargos, count(*) filter (where aspirante_id is not null) as con_aspirante,
       count(*) filter (where match_tipo = 'manual') as manuales
  from public.jce_juntas_2026;
