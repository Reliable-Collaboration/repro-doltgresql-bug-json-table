-- A jsonb array of two objects.
SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;

-- JSON_TABLE: one row for each element of the array.
SELECT *
FROM JSON_TABLE(
    '[{"a":1},{"a":2}]'::jsonb, '$[*]'
    COLUMNS (a int PATH '$.a')
) AS jt;
