-- PRE-FLIGHT F1.2 — Invertir FK a pilotos(id) → perfiles(id)
-- No cambia datos. Solo reporta estado.

-- Objetos básicos
select
  to_regclass('public.pilotos')  as pilotos,
  to_regclass('public.perfiles') as perfiles;

-- Consistencias 1:1 previas
select count(*) as pilotos_sin_perfil
from public.pilotos p
left join public.perfiles f on f.id = p.id
where f.id is null;

select count(*) as perfiles_sin_piloto
from public.perfiles f
left join public.pilotos p on p.id = f.id
where p.id is null;

-- DEFAULT en pilotos.id (esperado: false)
select atthasdef as pilotos_id_tiene_default
from pg_attribute
where attrelid = 'public.pilotos'::regclass and attname = 'id';

-- FK antigua (perfiles → pilotos)
select
  'old_fk_perfiles→pilotos' as check,
  (exists(select 1 from pg_constraint where conname='fk_perfiles_id_pilotos')) as exists,
  coalesce((select convalidated from pg_constraint where conname='fk_perfiles_id_pilotos'), false) as validated;

-- FK nueva (pilotos → perfiles)
select
  'new_fk_pilotos→perfiles' as check,
  (exists(select 1 from pg_constraint where conname='fk_pilotos_id_perfiles')) as exists,
  coalesce((select convalidated from pg_constraint where conname='fk_pilotos_id_perfiles'), false) as validated,
  (select confdeltype from pg_constraint where conname='fk_pilotos_id_perfiles') as on_delete,
  (select confupdtype from pg_constraint where conname='fk_pilotos_id_perfiles') as on_update;
