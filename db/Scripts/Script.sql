-- Estado de la FK y del entorno tras tu corrida
select conname, convalidated
from pg_constraint
where conname = 'fk_perfiles_id_pilotos';

-- ¿quedan perfiles sin piloto?
select count(*) as perfiles_sin_piloto
from public.perfiles f
left join public.pilotos p on p.id = f.id
where p.id is null;

-- ¿la columna pilotos.id quedó SIN default?
select atthasdef as pilotos_id_tiene_default
from pg_attribute
where attrelid = 'public.pilotos'::regclass and attname = 'id';

-- ¿existe y está activo el trigger?
select tgname, tgenabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relname='pilotos'
  and tgname='tg_pilotos_sync_empresa_from_centro_biu';

-- ¿están los índices?
select indexname
from pg_indexes
where schemaname='public' and tablename='pilotos'
  and indexname in ('ix_pilotos_empresa_id','ix_pilotos_centro_id');
