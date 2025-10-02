-- SMOKE F1.2 — Verificaciones tras invertir la FK

-- 1) Identidad 1:1 (pilotos deben tener perfil)
select 'pilotos_sin_perfil' as check,
       json_build_object('count', count(*)) as value,
       ''::text as details
from public.pilotos p
left join public.perfiles f on f.id = p.id
where f.id is null;

-- 2) Perfiles sin piloto (pueden existir por roles no-piloto)
select 'perfiles_sin_piloto' as check,
       json_build_object('count', count(*)) as value,
       json_agg(f.id)::text as details
from public.perfiles f
left join public.pilotos p on p.id = f.id
where p.id is null;

-- 3) Nueva FK existe, validada y con semántica esperada (on_delete='r' RESTRICT, on_update='c' CASCADE)
select 'fk_pilotos_id_perfiles_exists' as check,
       json_build_object(
         'exists',     exists(select 1 from pg_constraint where conname='fk_pilotos_id_perfiles'),
         'validated',  coalesce((select convalidated from pg_constraint where conname='fk_pilotos_id_perfiles'), false),
         'on_delete',  (select confdeltype from pg_constraint where conname='fk_pilotos_id_perfiles'),
         'on_update',  (select confupdtype from pg_constraint where conname='fk_pilotos_id_perfiles')
       ) as value,
       ''::text as details;

-- 4) FK antigua NO existe
select 'old_fk_perfiles_id_pilotos_absent' as check,
       json_build_object(
         'exists', not exists(select 1 from pg_constraint where conname='fk_perfiles_id_pilotos')
       ) as value,
       ''::text as details;

-- 5) Trigger de sincronización (empresa_id ← centro_id) sigue operativo (prueba en transacción con ROLLBACK)
BEGIN;
SET LOCAL search_path = public, app;

WITH p AS (SELECT id FROM public.pilotos LIMIT 1),
     c AS (SELECT id, empresa_id FROM public.centros LIMIT 1)
UPDATE public.pilotos t
   SET centro_id = c.id
  FROM p, c
 WHERE t.id = p.id;

select 'empresa_match_after_trigger' as check,
       json_build_object(
         'match',
         (select (t.empresa_id = c.empresa_id)
            from public.pilotos t, c
           where t.id = (select id from p))
       ) as value,
       ''::text as details;

ROLLBACK;
