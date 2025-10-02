select 'old_fk_perfiles_id_pilotos_absent' as check,
       json_build_object(
         'exists', exists(
            select 1
            from pg_constraint con
            join pg_class c on c.oid=con.conrelid
            join pg_namespace n on n.oid=c.relnamespace
            join pg_class rc on rc.oid=con.confrelid
            join pg_namespace rn on rn.oid=rc.relnamespace
            where con.contype='f'
              and n.nspname='public' and c.relname='perfiles'
              and rn.nspname='public' and rc.relname='pilotos'
         )
       ) as value,
       ''::text as details;
