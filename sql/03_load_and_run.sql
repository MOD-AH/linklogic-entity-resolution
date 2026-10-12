-- Load records.csv, then stream every record through resolve_record() in arrival order.
-- Run from the data/ directory:  psql -d linklogic -v use_alias=1 [-v t_auto=0.75] -f ../sql/03_load_and_run.sql
\set ON_ERROR_STOP on
TRUNCATE audit_log, review_queue, entity_parent, match_link, clean_record, clean_alias, source_record, golden_entity RESTART IDENTITY CASCADE;
DROP TABLE IF EXISTS stage, stage_alias, run_log;

CREATE TABLE stage (source text, source_key text, name_raw text, country text, city text,
                    postcode text, truth_group text, variant_kind text, arrival int);
\copy stage FROM 'records.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO source_record(record_id, source, source_key, raw, truth_group)
SELECT arrival + 1, source, source_key,
       jsonb_build_object('name', name_raw, 'variant', variant_kind), truth_group
FROM stage;

INSERT INTO clean_record(record_id, name_raw, name_norm, country, city, postcode)
SELECT arrival + 1, name_raw, normalize_name(name_raw), country::char(2), city, NULLIF(postcode, '')
FROM stage;
CREATE TABLE stage_alias (lei text, alias text);
\copy stage_alias FROM 'aliases.csv' WITH (FORMAT csv, HEADER true)
INSERT INTO clean_alias(record_id, name_norm, country)
SELECT s.record_id, normalize_name(a.alias), c.country
FROM stage_alias a
JOIN source_record s ON s.source = 'GLEIF' AND s.source_key = a.lei
JOIN clean_record c ON c.record_id = s.record_id
WHERE :use_alias = 1 AND normalize_name(a.alias) <> '' AND normalize_name(a.alias) <> c.name_norm;
SELECT setval('source_record_record_id_seq', (SELECT max(record_id) FROM source_record));

\if :{?t_auto}
\else
  \set t_auto 0.75
\endif
SELECT set_config('linklogic.t_auto', :'t_auto', false);
CREATE TABLE run_log (record_id bigint PRIMARY KEY, ms double precision);
DO $$
DECLARE r record; t0 timestamptz;
BEGIN
  FOR r IN SELECT record_id FROM source_record ORDER BY record_id LOOP
    t0 := clock_timestamp();
    PERFORM resolve_record(r.record_id);
    INSERT INTO run_log VALUES (r.record_id, extract(epoch FROM clock_timestamp() - t0) * 1000);
  END LOOP;
END $$;
ANALYZE;
