-- DBeaver ociosas (no toca la tuya actual)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND application_name ILIKE 'DBeaver%'
  AND state IN ('idle','idle in transaction','idle in transaction (aborted)');

-- Clientes sin nombre, ociosos hace >10 min
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE coalesce(application_name,'') = ''
  AND state IN ('idle','idle in transaction','idle in transaction (aborted)')
  AND now()-state_change > interval '10 minutes';
