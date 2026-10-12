-- Controlled check: group companies with shared prefixes must not merge. Country TT keeps it apart from the sample.
INSERT INTO source_record(record_id, source, source_key, raw, truth_group) VALUES
 (2000001,'TATA','1','{}','tm'),(2000002,'TATA','2','{}','tm'),(2000003,'TATA','3','{}','ts'),
 (2000004,'TATA','4','{}','tmf'),(2000005,'TATA','5','{}','tm'),(2000006,'TATA','6','{}','tcs');
INSERT INTO clean_record(record_id,name_raw,name_norm,country,postcode) VALUES
 (2000001,'Tata Motors Limited',normalize_name('Tata Motors Limited'),'TT','400001'),
 (2000002,'TATA MOTORS LTD.',normalize_name('TATA MOTORS LTD.'),'TT','400001'),
 (2000003,'Tata Steel Limited',normalize_name('Tata Steel Limited'),'TT','400001'),
 (2000004,'Tata Motors Finance Ltd',normalize_name('Tata Motors Finance Ltd'),'TT','400099'),
 (2000005,'Tata Motor Limited',normalize_name('Tata Motor Limited'),'TT','400001'),
 (2000006,'Tata Consultancy Services Limited',normalize_name('Tata Consultancy Services Limited'),'TT','400021');
SELECT resolve_record(i) FROM generate_series(2000001,2000006) i;
SELECT c.name_raw, l.entity_id, round(l.score::numeric,2) AS score, l.decision
FROM match_link l JOIN clean_record c USING (record_id) WHERE c.country='TT' ORDER BY l.record_id;
SELECT c.name_raw AS queued_record, g.canonical_name AS candidate_entity, round(q.score::numeric,2) AS score
FROM review_queue q JOIN clean_record c USING (record_id) JOIN golden_entity g ON g.entity_id=q.candidate_entity_id WHERE c.country='TT';
