-- Datum / Mymir agent memory schema.
-- Working / episodic / semantic / procedural decomposition.
-- Based on the design in ~/vault/research/datum-postgres-memory-2026.md lines 708-1125.
-- Cross-checked against MemGPT/Letta tiered memory and mem0 fact-extraction (drone research, 2026-05-20).
--
-- Apply on a ParadeDB-on-PG17 database (pg_search + pgvector required).
-- Idempotent: drops everything in the memory schema and recreates it.
--
-- Notes on divergence from report:
--   1. Messages table is NOT partitioned in this migration. At 15k rows in Datum
--      today, time partitioning is premature. Add a follow-up migration when
--      a single tenant exceeds ~10M messages.
--   2. Embedding dim 1536 to match text-embedding-3-small (orchestrator default).
--      Mymir bench uses 384 (MiniLM); claim/procedure embeddings use the larger model.
--   3. tenant_id and agent_id stay BIGINT to match the report. Mapping to Mymir's
--      UUID user_id is handled in application code, not the schema.

CREATE SCHEMA IF NOT EXISTS memory;
SET search_path TO memory, public;

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;

-- ---------- agents ----------
CREATE TABLE memory.agents (
    agent_id           BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    name               TEXT NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tenant_id, name)
);

-- ---------- conversations ----------
CREATE TABLE memory.conversations (
    conversation_id    BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    agent_id           BIGINT NOT NULL REFERENCES memory.agents(agent_id) ON DELETE CASCADE,
    external_thread_id TEXT,
    title              TEXT,
    started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at           TIMESTAMPTZ,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tenant_id, external_thread_id)
);

CREATE INDEX idx_conversations_agent_time
    ON memory.conversations (agent_id, started_at DESC);

-- ---------- messages ----------
-- Unpartitioned for now; see header note.
CREATE TABLE memory.messages (
    message_id         BIGSERIAL,
    tenant_id          BIGINT NOT NULL,
    conversation_id    BIGINT NOT NULL REFERENCES memory.conversations(conversation_id) ON DELETE CASCADE,
    role               TEXT NOT NULL CHECK (role IN ('system','developer','user','assistant','tool')),
    turn_index         INTEGER NOT NULL,
    content            TEXT NOT NULL,
    token_count        INTEGER,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_message_id  TEXT,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (conversation_id, message_id)
);

CREATE INDEX idx_messages_conversation_time
    ON memory.messages (conversation_id, created_at DESC);

CREATE INDEX idx_messages_tenant_time
    ON memory.messages (tenant_id, created_at DESC);

-- ---------- episodes ----------
CREATE TABLE memory.episodes (
    episode_id         BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    conversation_id    BIGINT NOT NULL REFERENCES memory.conversations(conversation_id) ON DELETE CASCADE,
    episode_type       TEXT NOT NULL DEFAULT 'dialogue',
    start_message_id   BIGINT NOT NULL,
    end_message_id     BIGINT NOT NULL,
    start_at           TIMESTAMPTZ NOT NULL,
    end_at             TIMESTAMPTZ NOT NULL,
    summary            TEXT NOT NULL,
    salience_score     DOUBLE PRECISION NOT NULL DEFAULT 0,
    importance_score   DOUBLE PRECISION NOT NULL DEFAULT 0,
    reflection_text    TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE memory.episode_messages (
    episode_id         BIGINT NOT NULL REFERENCES memory.episodes(episode_id) ON DELETE CASCADE,
    conversation_id    BIGINT NOT NULL,
    message_id         BIGINT NOT NULL,
    PRIMARY KEY (episode_id, message_id),
    FOREIGN KEY (conversation_id, message_id)
        REFERENCES memory.messages(conversation_id, message_id) ON DELETE CASCADE
);

CREATE INDEX idx_episodes_conversation_time
    ON memory.episodes (conversation_id, start_at DESC);

CREATE INDEX idx_episodes_salience
    ON memory.episodes (tenant_id, salience_score DESC, end_at DESC);

-- ---------- claims (semantic memory) ----------
CREATE TABLE memory.claims (
    claim_id           BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    agent_id           BIGINT NOT NULL REFERENCES memory.agents(agent_id) ON DELETE CASCADE,
    entity_key         TEXT,
    subject            TEXT NOT NULL,
    predicate          TEXT NOT NULL,
    object_text        TEXT NOT NULL,
    normalized_text    TEXT NOT NULL,
    claim_type         TEXT NOT NULL DEFAULT 'fact',
    confidence         DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','superseded','contradicted','deprecated','pending')),
    support_count      INTEGER NOT NULL DEFAULT 1,
    superseded_by      BIGINT REFERENCES memory.claims(claim_id) ON DELETE SET NULL,
    valid_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_to           TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_episode_id  BIGINT REFERENCES memory.episodes(episode_id) ON DELETE SET NULL,
    source_message_id  BIGINT,
    source_type        TEXT NOT NULL DEFAULT 'llm_extraction',
    provenance         JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_claims_entity_predicate
    ON memory.claims (tenant_id, entity_key, predicate, status);

CREATE INDEX idx_claims_subject_predicate
    ON memory.claims (tenant_id, subject, predicate);

CREATE INDEX idx_claims_created_at
    ON memory.claims (tenant_id, created_at DESC);

CREATE INDEX idx_claims_status_valid
    ON memory.claims (tenant_id, status, valid_from DESC);

-- ---------- claim_mentions (provenance) ----------
CREATE TABLE memory.claim_mentions (
    claim_mention_id   BIGSERIAL PRIMARY KEY,
    claim_id           BIGINT NOT NULL REFERENCES memory.claims(claim_id) ON DELETE CASCADE,
    conversation_id    BIGINT NOT NULL REFERENCES memory.conversations(conversation_id) ON DELETE CASCADE,
    message_id         BIGINT NOT NULL,
    extracted_by       TEXT NOT NULL DEFAULT 'llm',
    extraction_model   TEXT,
    extraction_prompt  TEXT,
    evidence_span      JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (conversation_id, message_id)
        REFERENCES memory.messages(conversation_id, message_id) ON DELETE CASCADE
);

CREATE INDEX idx_claim_mentions_claim
    ON memory.claim_mentions (claim_id);

-- ---------- claim_embeddings ----------
CREATE TABLE memory.claim_embeddings (
    claim_id           BIGINT PRIMARY KEY REFERENCES memory.claims(claim_id) ON DELETE CASCADE,
    embedding_model    TEXT NOT NULL,
    embedding_dim      INTEGER NOT NULL,
    embedding          VECTOR(1536),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_claim_embeddings_hnsw
    ON memory.claim_embeddings USING hnsw (embedding vector_cosine_ops);

-- ---------- claim_relations (contradiction / supersede graph) ----------
CREATE TABLE memory.claim_relations (
    relation_id        BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    from_claim_id      BIGINT NOT NULL REFERENCES memory.claims(claim_id) ON DELETE CASCADE,
    to_claim_id        BIGINT NOT NULL REFERENCES memory.claims(claim_id) ON DELETE CASCADE,
    relation_type      TEXT NOT NULL CHECK (relation_type IN ('duplicates','supports','contradicts','supersedes','refines')),
    score              DOUBLE PRECISION NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (from_claim_id, to_claim_id, relation_type)
);

CREATE INDEX idx_claim_relations_from
    ON memory.claim_relations (from_claim_id);

CREATE INDEX idx_claim_relations_to
    ON memory.claim_relations (to_claim_id);

-- ---------- working_memory_items ----------
CREATE TABLE memory.working_memory_items (
    working_item_id    BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    conversation_id    BIGINT NOT NULL REFERENCES memory.conversations(conversation_id) ON DELETE CASCADE,
    item_type          TEXT NOT NULL CHECK (item_type IN ('message','claim','summary','tool_result','procedure')),
    ref_id             BIGINT NOT NULL,
    priority_score     DOUBLE PRECISION NOT NULL DEFAULT 0,
    recency_score      DOUBLE PRECISION NOT NULL DEFAULT 0,
    salience_score     DOUBLE PRECISION NOT NULL DEFAULT 0,
    llm_relevance_score DOUBLE PRECISION NOT NULL DEFAULT 0,
    last_accessed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_working_memory_rank
    ON memory.working_memory_items (conversation_id, priority_score DESC, salience_score DESC, last_accessed_at DESC);

-- ---------- consolidation_jobs ----------
CREATE TABLE memory.consolidation_jobs (
    job_id             BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    conversation_id    BIGINT NOT NULL REFERENCES memory.conversations(conversation_id) ON DELETE CASCADE,
    job_type           TEXT NOT NULL CHECK (job_type IN ('episode_summary','claim_extraction','reflection','procedure_distillation')),
    status             TEXT NOT NULL CHECK (status IN ('queued','running','succeeded','failed')),
    scheduled_for      TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at         TIMESTAMPTZ,
    finished_at        TIMESTAMPTZ,
    error_text         TEXT,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_consolidation_jobs_status
    ON memory.consolidation_jobs (status, scheduled_for);

-- ---------- procedures (procedural memory) ----------
CREATE TABLE memory.procedures (
    procedure_id       BIGSERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL,
    agent_id           BIGINT NOT NULL REFERENCES memory.agents(agent_id) ON DELETE CASCADE,
    name               TEXT NOT NULL,
    description        TEXT,
    goal_tags          TEXT[] NOT NULL DEFAULT '{}',
    parameter_schema   JSONB NOT NULL DEFAULT '{}'::jsonb,
    body               JSONB NOT NULL,
    version            INTEGER NOT NULL DEFAULT 1,
    status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','deprecated','draft')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tenant_id, agent_id, name, version)
);

CREATE TABLE memory.procedure_steps (
    step_id            BIGSERIAL PRIMARY KEY,
    procedure_id       BIGINT NOT NULL REFERENCES memory.procedures(procedure_id) ON DELETE CASCADE,
    step_index         INTEGER NOT NULL,
    step_type          TEXT NOT NULL CHECK (step_type IN ('thought','tool_call','condition','branch','output')),
    instruction        TEXT NOT NULL,
    tool_name          TEXT,
    tool_args_template JSONB,
    condition_expr     TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (procedure_id, step_index)
);

CREATE TABLE memory.procedure_embeddings (
    procedure_id       BIGINT PRIMARY KEY REFERENCES memory.procedures(procedure_id) ON DELETE CASCADE,
    embedding_model    TEXT NOT NULL,
    embedding_dim      INTEGER NOT NULL,
    embedding          VECTOR(1536),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_procedure_embeddings_hnsw
    ON memory.procedure_embeddings USING hnsw (embedding vector_cosine_ops);
