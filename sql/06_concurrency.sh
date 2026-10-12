#!/bin/zsh
# Concurrency test: 400 new companies, each arriving twice (second copy re-cased and re-suffixed)
# on two different connections at the same moment. Correct result: exactly 400 entities.
# Run once with the advisory lock (country ZZ) and once with the lock removed (country ZY).
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH
cd "$(dirname "$0")" || exit 1
DB=linklogic
WORKERS=8

# Variant of the resolver with the advisory lock line removed
sed -e 's/resolve_record(/resolve_record_nolock(/' -e '/pg_advisory_xact_lock/d' 02_resolver.sql \
  | psql -q -d $DB >/dev/null 2>&1

psql -q -d $DB <<'SQL'
DROP TABLE IF EXISTS conc_queue;
CREATE TABLE conc_queue (record_id bigint PRIMARY KEY, worker int, seq int, mode text);
WITH names AS (
  SELECT i, initcap(substr(md5('co' || i), 1, 7)) || ' Holdings' AS base FROM generate_series(1, 400) i
), ids AS (
  SELECT i, base, 1000000 + 2*i AS a, 1000001 + 2*i AS b FROM names
), src AS (
  INSERT INTO source_record(record_id, source, source_key, raw, truth_group)
  SELECT x.id, 'CONC', x.id::text, '{}', 'conc-' || i
  FROM ids, LATERAL (VALUES (a), (b), (a + 1000000), (b + 1000000)) AS x(id)
  RETURNING record_id
), c AS (
  INSERT INTO clean_record(record_id, name_raw, name_norm, country)
  SELECT x.id,
         CASE WHEN x.id % 2 = 0 THEN base || ' Limited' ELSE upper(base) || ' LTD' END,
         normalize_name(base), x.cty::char(2)
  FROM ids, LATERAL (VALUES (a, 'ZZ'), (b, 'ZZ'), (a + 1000000, 'ZY'), (b + 1000000, 'ZY')) AS x(id, cty)
  RETURNING record_id
)
INSERT INTO conc_queue
SELECT x.id, (CASE WHEN x.id % 2 = 0 THEN i ELSE i + 1 END) % 8, i, x.mode
FROM ids, LATERAL (VALUES (a, 'lock'), (b, 'lock'), (a + 1000000, 'nolock'), (b + 1000000, 'nolock')) AS x(id, mode);
SQL

run_mode() {  # mode, function name
  for k in $(seq 0 $((WORKERS-1))); do
    psql -q -d $DB -c "SELECT $2(record_id) FROM (SELECT record_id FROM conc_queue WHERE mode='$1' AND worker=$k ORDER BY seq) q" >/dev/null &
  done
  wait
}
t0=$(date +%s.%N); run_mode lock resolve_record;          t1=$(date +%s.%N)
run_mode nolock resolve_record_nolock;                    t2=$(date +%s.%N)

psql -d $DB <<SQL
SELECT 'with advisory lock' AS variant, count(*) AS entities_created, 400 AS expected,
       count(*) - 400 AS duplicates FROM golden_entity WHERE country = 'ZZ'
UNION ALL
SELECT 'without lock', count(*), 400, count(*) - 400 FROM golden_entity WHERE country = 'ZY';
SQL
echo "elapsed lock: $(echo "$t1 - $t0" | bc) s, nolock: $(echo "$t2 - $t1" | bc) s"
