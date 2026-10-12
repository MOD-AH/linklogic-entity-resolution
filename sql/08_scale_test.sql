-- Scale check: 500,000 synthetic names in 5 countries, with and without the GIN trigram index.
DROP TABLE IF EXISTS scale_test;
CREATE TABLE scale_test AS
SELECT g AS id, (ARRAY['IN','GB','DE','FR','US'])[1 + g % 5]::char(2) AS country,
       substr(md5('a' || g), 1, 6) || ' ' || substr(md5('b' || g), 1, 5) || ' ' ||
       (ARRAY['holdings','industries','trading','logistics','systems','capital','steel','motors'])[1 + g % 8] AS name_norm
FROM generate_series(1, 500000) g;
ANALYZE scale_test;
\echo '--- without GIN (country filter only)'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT id, similarity(name_norm, 'a1b2c3 d4e5f holdings') FROM scale_test
 WHERE country='IN' AND name_norm % 'a1b2c3 d4e5f holdings' ORDER BY 2 DESC LIMIT 10;
CREATE INDEX scale_trgm ON scale_test USING gin (name_norm gin_trgm_ops);
CREATE INDEX scale_country ON scale_test (country);
ANALYZE scale_test;
\echo '--- with GIN trigram index'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT id, similarity(name_norm, 'a1b2c3 d4e5f holdings') FROM scale_test
 WHERE country='IN' AND name_norm % 'a1b2c3 d4e5f holdings' ORDER BY 2 DESC LIMIT 10;
SELECT pg_size_pretty(pg_relation_size('scale_trgm')) AS gin_size, pg_size_pretty(pg_relation_size('scale_test')) AS table_size;
