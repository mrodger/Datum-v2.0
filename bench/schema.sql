-- bench/schema.sql
-- Isolated benchmark table for Batch 2 sub-plan 1.
-- Does not touch any Mymir application table.

CREATE EXTENSION IF NOT EXISTS pg_search;
CREATE EXTENSION IF NOT EXISTS vector;

DROP TABLE IF EXISTS bench_docs CASCADE;

CREATE TABLE bench_docs (
    id        SERIAL PRIMARY KEY,
    title     TEXT NOT NULL,
    body      TEXT NOT NULL,
    embedding vector(384)
);

-- BM25 index over title+body (pg_search BM25 index).
CREATE INDEX bench_docs_bm25
    ON bench_docs
    USING bm25 (id, title, body)
    WITH (key_field = 'id');

-- HNSW index for cosine similarity over 384-d embeddings.
CREATE INDEX bench_docs_embedding_hnsw
    ON bench_docs
    USING hnsw (embedding vector_cosine_ops);
