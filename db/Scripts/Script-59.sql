SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = current_user            -- solo tus sesiones
  AND pid <> pg_backend_pid()           -- no te mates a ti
  AND application_name ILIKE 'DBeaver%' -- editores DBeaver
  AND state IN ('idle','idle in transaction','idle in transaction (aborted)');
