-- ¿Existen FKs que referencien pilotos.rut?
WITH rut_att AS (
  SELECT attnum
  FROM pg_attribute
  WHERE attrelid = 'public.pilotos'::regclass
    AND attname  = 'rut'
),
fks AS (
  SELECT fk.conname,
         fk.conrelid::regclass  AS referencing_table,
         fk.confrelid::regclass AS referenced_table,
         (SELECT string_agg(a.attname, ',')
            FROM unnest(fk.confkey) WITH ORDINALITY ck(attnum, ord)
            JOIN pg_attribute a ON a.attrelid = fk.confrelid AND a.attnum = ck.attnum
         ) AS referenced_cols
  FROM pg_constraint fk
  WHERE fk.contype = 'f'
    AND fk.confrelid = 'public.pilotos'::regclass
    AND EXISTS (SELECT 1 FROM rut_att r WHERE r.attnum = ANY(fk.confkey))
)
SELECT * FROM fks;
