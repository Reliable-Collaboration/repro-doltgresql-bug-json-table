# DoltgreSQL 1.3.1: `JSON_TABLE` is refused with a syntax error at `COLUMNS`

On DoltgreSQL 1.3.1, a query that uses the SQL/JSON table function `JSON_TABLE` is refused at its `COLUMNS`
clause:

```
ERROR:  at or near "columns": syntax error
```

PostgreSQL 18.6 runs the same query and returns one row for each element of the array, `1` and `2`.

Reported upstream: https://github.com/dolthub/doltgresql/issues/3331

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the two images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-json-table.git
cd repro-doltgresql-bug-json-table
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in throwaway containers, waits until each accepts
connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container, and prints
the two outputs side by side. It exits 0 when DoltgreSQL's output is identical to PostgreSQL's and 1 when it
differs, and removes both containers either way.

To try another DoltgreSQL release, name its image (`POSTGRES_IMAGE` does the same for PostgreSQL):

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-json-table-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-json-table-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-json-table-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-json-table-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-json-table-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-json-table-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-json-table-postgres repro-doltgresql-bug-json-table-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few seconds
and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A jsonb array of two objects.
SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;

-- JSON_TABLE: one row for each element of the array.
SELECT *
FROM JSON_TABLE(
    '[{"a":1},{"a":2}]'::jsonb, '$[*]'
    COLUMNS (a int PATH '$.a')
) AS jt;
```

## Expected behavior

Both statements succeed, and `JSON_TABLE` returns one row for each element of the array. This is what
PostgreSQL 18.6 does:

```
-- A jsonb array of two objects.
SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;
         doc          
----------------------
 [{"a": 1}, {"a": 2}]
(1 row)

-- JSON_TABLE: one row for each element of the array.
SELECT *
FROM JSON_TABLE(
    '[{"a":1},{"a":2}]'::jsonb, '$[*]'
    COLUMNS (a int PATH '$.a')
) AS jt;
 a 
---
 1
 2
(2 rows)
```

## Actual behavior

The document itself is returned as on PostgreSQL, but the `JSON_TABLE` query fails. This is what DoltgreSQL
1.3.1 does:

```
-- A jsonb array of two objects.
SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;
         doc          
----------------------
 [{"a": 1}, {"a": 2}]
(1 row)

-- JSON_TABLE: one row for each element of the array.
SELECT *
FROM JSON_TABLE(
    '[{"a":1},{"a":2}]'::jsonb, '$[*]'
    COLUMNS (a int PATH '$.a')
) AS jt;
psql:/tmp/repro.sql:9: ERROR:  at or near "columns": syntax error
```

## Side by side

The full output of `./repro.sh`. `diff` cuts lines that are wider than its column, so the error on the right
is shortened here; it is shown in full under Actual behavior.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- A jsonb array of two objects.                              -- A jsonb array of two objects.
SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;                     SELECT '[{"a":1},{"a":2}]'::jsonb AS doc;
         doc                                                           doc          
----------------------                                        ----------------------
 [{"a": 1}, {"a": 2}]                                          [{"a": 1}, {"a": 2}]
(1 row)                                                       (1 row)

-- JSON_TABLE: one row for each element of the array.         -- JSON_TABLE: one row for each element of the array.
SELECT *                                                      SELECT *
FROM JSON_TABLE(                                              FROM JSON_TABLE(
    '[{"a":1},{"a":2}]'::jsonb, '$[*]'                            '[{"a":1},{"a":2}]'::jsonb, '$[*]'
    COLUMNS (a int PATH '$.a')                                    COLUMNS (a int PATH '$.a')
) AS jt;                                                      ) AS jt;
 a                                                          | psql:/tmp/repro.sql:9: ERROR:  at or near "columns": syntax
---                                                         <
 1                                                          <
 2                                                          <
(2 rows)                                                    <
                                                            <

Result: DoltgreSQL's output differs from PostgreSQL's on 1 line(s), marked with |.
```

## Other observations

Each was run with `psql` on DoltgreSQL 1.3.1 and on PostgreSQL 18.6, in containers from the same images:

- Every other form of `JSON_TABLE` tried answers the same `at or near "columns": syntax error`: lower case
  (`columns (a int path '$.a')`), `COLUMNS (a int)` without `PATH`, `n FOR ORDINALITY`, an untyped document
  (`JSON_TABLE('[{"a":1},{"a":2}]', '$[*]'`), a `json` document, and
  `JSON_TABLE(t.doc, '$[*]' COLUMNS (a int PATH '$.a'))` over a table column, after a comma and after
  `CROSS JOIN LATERAL`. PostgreSQL returns the rows for each.
- `CREATE VIEW v AS SELECT t.id, jt.a FROM t, JSON_TABLE(t.doc, '$[*]' COLUMNS (a int PATH '$.a')) AS jt;`
  answers the same error. PostgreSQL creates the view.
- With a `PASSING` clause (`'$[*] ? (@.a > $x)' PASSING 1 AS x`) the error is
  `at or near "passing": syntax error`. PostgreSQL returns the one row that matches.
- Without the `COLUMNS` clause, `SELECT * FROM JSON_TABLE('[{"a":1},{"a":2}]'::jsonb, '$[*]');` answers
  `unsupported JSON function: json_table`. PostgreSQL requires the clause: `syntax error at or near ")"`.
- `SELECT * FROM jsonb_array_elements('[{"a":1},{"a":2}]'::jsonb);` answers
  `table function: 'jsonb_array_elements' not found`, and
  `SELECT jsonb_array_elements('[{"a":1},{"a":2}]'::jsonb) AS e;` answers
  `function: 'jsonb_array_elements' not found`. PostgreSQL returns the two elements for both.
- `SELECT * FROM jsonb_to_recordset('[{"a":1},{"a":2}]'::jsonb) AS r(a int);` answers
  `at or near "int": syntax error`. PostgreSQL returns `1` and `2`.
- `SELECT * FROM jsonb_each('{"a":1}'::jsonb);` answers `table function: 'jsonb_each' not found`. PostgreSQL
  returns one row.
- These return the same result on both: `jsonb_array_length`, the operators in
  `'[{"a":1},{"a":2}]'::jsonb -> 1 ->> 'a'`, `SELECT * FROM generate_series(1, 2) AS g;`,
  `SELECT * FROM unnest(ARRAY[1, 2]) AS u;` and `JSON_VALUE('{"a":1}'::jsonb, '$.a')`.
- With `RETURNING int`, `JSON_VALUE` answers `at or near "returning": syntax error`; `JSON_QUERY` and
  `JSON_EXISTS` answer `function: 'json_query' not found` and `function: 'json_exists' not found`, and
  `SELECT '$[*]'::jsonpath;` answers ``unable to resolve type `jsonpath` ``. PostgreSQL runs all four.
- `SELECT version();` answers `PostgreSQL 15.5` on DoltgreSQL 1.3.1. PostgreSQL added `JSON_TABLE` in version 17 ([release notes](https://www.postgresql.org/docs/17/release-17.html)).

## Environment

- DoltgreSQL 1.3.1: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its `psql` is 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Ubuntu 26.04.1 LTS under WSL 2 (Linux
  6.18.33.2-microsoft-standard-WSL2, x86_64).
