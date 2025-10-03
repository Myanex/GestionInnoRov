-- FK nueva existe y validada
select conname, convalidated, confdeltype as on_delete, confupdtype as on_update
from pg_constraint
where conname='fk_pilotos_id_perfiles';

-- No quedan FKs public.perfiles → public.pilotos
select exists(
  select 1
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_class rc on rc.oid=con.confrelid
  join pg_namespace rn on rn.oid=rc.relnamespace
  where con.contype='f'
    and n.nspname='public' and c.relname='perfiles'
    and rn.nspname='public' and rc.relname='pilotos'
) as old_fk_present;  -- esperado: false
