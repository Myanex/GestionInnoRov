select conname, convalidated
from pg_constraint
where conname = 'fk_perfiles_id_pilotos';

