-- Pairwise precision / recall / F0.5 of the produced entities against truth_group.
WITH e AS (
  SELECT l.entity_id, s.truth_group
  FROM match_link l JOIN source_record s USING (record_id)
),
ent_pairs AS (SELECT sum(n*(n-1)/2) AS p FROM (SELECT count(*)::bigint n FROM e GROUP BY entity_id) x),
truth_pairs AS (SELECT sum(n*(n-1)/2) AS p FROM (SELECT count(*)::bigint n FROM e GROUP BY truth_group) x),
both_pairs AS (SELECT sum(n*(n-1)/2) AS p FROM (SELECT count(*)::bigint n FROM e GROUP BY entity_id, truth_group) x)
SELECT (SELECT count(*) FROM source_record)                      AS records,
       (SELECT count(*) FROM golden_entity)                       AS entities,
       (SELECT count(DISTINCT truth_group) FROM source_record)    AS true_entities,
       round((b.p / NULLIF(ep.p,0))::numeric, 4)                  AS precision,
       round((b.p / NULLIF(tp.p,0))::numeric, 4)                  AS recall,
       round((1.25 * (b.p/ep.p) * (b.p/tp.p) / (0.25 * (b.p/ep.p) + (b.p/tp.p)))::numeric, 4) AS f0_5
FROM ent_pairs ep, truth_pairs tp, both_pairs b;

SELECT decision, count(*) FROM match_link GROUP BY decision ORDER BY 1;
SELECT count(*) AS open_reviews FROM review_queue WHERE status = 'open';
SELECT round(avg(ms)::numeric,2) AS avg_ms,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY ms))::numeric,2) AS p50_ms,
       round((percentile_cont(0.95) WITHIN GROUP (ORDER BY ms))::numeric,2) AS p95_ms,
       round(max(ms)::numeric,2) AS max_ms FROM run_log;
