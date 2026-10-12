-- LinkLogic entity resolution schema (PostgreSQL 17, pg_trgm, pgvector)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

DROP TABLE IF EXISTS audit_log, review_queue, entity_parent, match_link,
                     clean_record, clean_alias, source_record, golden_entity CASCADE;

CREATE TABLE source_record (
    record_id    bigserial PRIMARY KEY,
    source       text        NOT NULL,            -- 'GLEIF', 'MCA', 'NOISY_COPY'
    source_key   text        NOT NULL,            -- LEI, CIN, ...
    raw          jsonb       NOT NULL,
    truth_group  text,                            -- ground-truth id, evaluation only
    ingested_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source, source_key)
);

CREATE TABLE clean_record (
    record_id  bigint PRIMARY KEY REFERENCES source_record ON DELETE CASCADE,
    name_raw   text NOT NULL,
    name_norm  text NOT NULL,
    country    char(2) NOT NULL,
    city       text,
    postcode   text,
    embedding  vector(256)                        -- Titan v2 at 256 dims, optional
);

CREATE TABLE clean_alias (                       -- registered trading names (GLEIF otherNames)
    alias_id   bigserial PRIMARY KEY,
    record_id  bigint NOT NULL REFERENCES source_record ON DELETE CASCADE,
    name_norm  text   NOT NULL,
    country    char(2) NOT NULL
);

CREATE TABLE golden_entity (
    entity_id      bigserial PRIMARY KEY,
    canonical_name text NOT NULL,
    country        char(2) NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE match_link (
    record_id  bigint PRIMARY KEY REFERENCES source_record ON DELETE CASCADE,
    entity_id  bigint NOT NULL REFERENCES golden_entity,
    score      real   NOT NULL,
    decision   text   NOT NULL CHECK (decision IN ('auto_merge','new_entity','review_accepted')),
    decided_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE entity_parent (                      -- GLEIF Level 2 ownership
    child_entity_id  bigint NOT NULL REFERENCES golden_entity,
    parent_entity_id bigint NOT NULL REFERENCES golden_entity,
    relation         text   NOT NULL DEFAULT 'DIRECT_PARENT',
    PRIMARY KEY (child_entity_id, parent_entity_id),
    CHECK (child_entity_id <> parent_entity_id)
);

CREATE TABLE review_queue (
    review_id           bigserial PRIMARY KEY,
    record_id           bigint NOT NULL REFERENCES source_record ON DELETE CASCADE,
    candidate_entity_id bigint NOT NULL REFERENCES golden_entity,
    score               real   NOT NULL,
    status              text   NOT NULL DEFAULT 'open' CHECK (status IN ('open','accepted','rejected')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (record_id, candidate_entity_id)
);

CREATE TABLE audit_log (
    audit_id   bigserial PRIMARY KEY,
    at         timestamptz NOT NULL DEFAULT now(),
    actor      text   NOT NULL DEFAULT current_user,
    action     text   NOT NULL,
    record_id  bigint,
    entity_id  bigint,
    detail     jsonb
);

-- Blocking and lookup indexes
CREATE INDEX clean_name_trgm ON clean_record USING gin (name_norm gin_trgm_ops);
CREATE INDEX alias_name_trgm ON clean_alias USING gin (name_norm gin_trgm_ops);
CREATE INDEX clean_country   ON clean_record (country);
CREATE INDEX clean_postcode  ON clean_record (country, postcode);
CREATE INDEX link_entity     ON match_link (entity_id);
CREATE INDEX review_open     ON review_queue (status) WHERE status = 'open';
CREATE INDEX parent_by_parent ON entity_parent (parent_entity_id);

-- Name normalisation: lower-case, strip punctuation and legal-form words
CREATE OR REPLACE FUNCTION normalize_name(n text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT btrim(regexp_replace(
           regexp_replace(
             regexp_replace(lower(n), '[^a-z0-9 ]+', ' ', 'g'),
             '\m(pvt|private|ltd|limited|llp|inc|incorporated|corp|corporation|co|company|plc|gmbh|sa|sas|sarl|ag|bv|nv|llc|oyj|ab|as|spa|srl|the)\M', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

-- Numbers inside a name distinguish fund series and numbered subsidiaries (2055 vs 2070)
CREATE OR REPLACE FUNCTION digit_tokens(n text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(string_agg(m[1], ' ' ORDER BY m[1]), '')
  FROM regexp_matches(n, '(\d+)', 'g') AS m
$$;

-- Audit every change of a record's golden entity
CREATE OR REPLACE FUNCTION trg_audit_link() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO audit_log(action, record_id, entity_id, detail)
  VALUES (TG_OP || '_LINK', NEW.record_id, NEW.entity_id,
          jsonb_build_object('score', NEW.score, 'decision', NEW.decision));
  RETURN NEW;
END $$;
CREATE TRIGGER audit_match_link AFTER INSERT OR UPDATE ON match_link
  FOR EACH ROW EXECUTE FUNCTION trg_audit_link();
