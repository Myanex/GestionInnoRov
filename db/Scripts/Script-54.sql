SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = current_user
  AND application_name ILIKE 'DBeaver%';
