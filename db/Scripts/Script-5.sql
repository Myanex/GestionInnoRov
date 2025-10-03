-- a) TODAS las FKs de public.perfiles (para saber nombres y a qué apuntan)
select
  con.conname,
  con.convalidated,
  n.nspname  as src_schema,
  c.relname  as src_table,
  rn.nspname as ref_schema,
  rc.relname as ref_table,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class c   on c.oid  = con.conrelid
join pg_namespace n  on n.oid  = c.relnamespace
join pg_class rc  on rc.oid = con.confrelid
join pg_namespace rn on rn.oid = rc.relnamespace
where con.contype='f'
  and n.nspname='public'
  and c.relname='perfiles'
order by con.conname;

-- b) Solo las que apuntan a public.pilotos
select
  con.conname, con.convalidated,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class c   on c.oid  = con.conrelid
join pg_namespace n  on n.oid  = c.relnamespace
join pg_class rc  on rc.oid = con.confrelid
join pg_namespace rn on rn.oid = rc.relnamespace
where con.contype='f'
  and n.nspname='public' and c.relname='perfiles'
  and rn.nspname='public' and rc.relname='pilotos'
order by con.conname;
