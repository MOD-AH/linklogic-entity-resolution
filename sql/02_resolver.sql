-- Resolver: block by country + trigram index, score, decide, link. One call per record.
-- A candidate must carry the same numbers as the record (digit_tokens), otherwise it is skipped.
-- score >= t_auto and (postcode agrees or score >= t_strong) -> merge into existing entity
-- score >= t_review otherwise                                 -> new entity + review queue row
-- else                                                        -> new entity
-- Thresholds come from the session settings linklogic.t_auto / t_strong / t_review
-- (defaults 0.75 / 0.90 / 0.55) so experiments can sweep them without editing the function.
DROP FUNCTION IF EXISTS resolve_record(bigint, real, real, real);
CREATE OR REPLACE FUNCTION resolve_record(p_record bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  t_auto   real := coalesce(nullif(current_setting('linklogic.t_auto',   true), '')::real, 0.75);
  t_strong real := coalesce(nullif(current_setting('linklogic.t_strong', true), '')::real, 0.90);
  t_review real := coalesce(nullif(current_setting('linklogic.t_review', true), '')::real, 0.55);
  r        clean_record%ROWTYPE;
  cand     record;
  best_ent bigint;
  best_sc  real;
  best_pc  text;
  ent      bigint;
  r_digits text;
BEGIN
  SELECT * INTO r FROM clean_record WHERE record_id = p_record;
  IF NOT FOUND THEN RAISE EXCEPTION 'record % not cleaned', p_record; END IF;
  r_digits := digit_tokens(r.name_norm);

  -- Records sharing a blocking key are resolved one at a time, so two near-duplicates
  -- arriving together cannot both create a new entity.
  PERFORM pg_advisory_xact_lock(hashtext(r.country || ':' || split_part(r.name_norm, ' ', 1)));

  FOR cand IN
    SELECT l.entity_id, similarity(n.name_norm, r.name_norm) AS sc, c.postcode, n.name_norm
      FROM (SELECT record_id, name_norm FROM clean_record
             WHERE country = r.country AND record_id <> r.record_id AND name_norm % r.name_norm
            UNION ALL
            SELECT record_id, name_norm FROM clean_alias
             WHERE country = r.country AND name_norm % r.name_norm) n
      JOIN match_link   l ON l.record_id = n.record_id
      JOIN clean_record c ON c.record_id = n.record_id
     ORDER BY sc DESC, l.entity_id
     LIMIT 10
  LOOP
    IF digit_tokens(cand.name_norm) = r_digits THEN
      best_ent := cand.entity_id; best_sc := cand.sc; best_pc := cand.postcode;
      EXIT;
    END IF;
  END LOOP;

  IF best_ent IS NOT NULL AND best_sc >= t_auto
     AND (best_sc >= t_strong OR (r.postcode IS NOT NULL AND r.postcode = best_pc)) THEN
    INSERT INTO match_link(record_id, entity_id, score, decision)
    VALUES (p_record, best_ent, best_sc, 'auto_merge')
    ON CONFLICT (record_id) DO NOTHING;
    RETURN best_ent;
  END IF;

  INSERT INTO golden_entity(canonical_name, country) VALUES (r.name_raw, r.country)
  RETURNING entity_id INTO ent;
  INSERT INTO match_link(record_id, entity_id, score, decision)
  VALUES (p_record, ent, COALESCE(best_sc, 0), 'new_entity')
  ON CONFLICT (record_id) DO NOTHING;

  IF best_ent IS NOT NULL AND best_sc >= t_review THEN
    INSERT INTO review_queue(record_id, candidate_entity_id, score)
    VALUES (p_record, best_ent, best_sc) ON CONFLICT DO NOTHING;
  END IF;
  RETURN ent;
END $$;
