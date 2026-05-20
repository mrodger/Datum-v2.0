# bench/ — Hybrid Retrieval Benchmark Scaffold

Batch 2 sub-plan 1 deliverable. Isolated scaffold that measures BM25
(`pg_search`), vector (HNSW + `pgvector`), and Reciprocal Rank Fusion
(k=60) retrieval against a synthetic 1000-document corpus.

This does **not** touch any Mymir application table. Everything runs against
`bench_docs` only.

## Prerequisites

- Mymir's `db` service is up: `docker compose up -d db`
- Image is `paradedb/paradedb:latest-pg17` (provides `pg_search` + `pgvector`)
- Python 3.10+ with a venv

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install psycopg2-binary sentence-transformers numpy
```

First run of `sentence-transformers` will download `all-MiniLM-L6-v2`
(~90 MB) to `~/.cache/huggingface/`.

## Run

```bash
# 1. Create table + indices
docker exec -i mymir-db-1 psql -U mymir -d mymir < bench/schema.sql

# 2. Generate, embed, insert 1000 docs (~30 s)
python bench/seed.py

# 3. Run all three retrieval modes, write baseline-results.json
python bench/harness.py
```

## What gets measured

- **Latency**: per-call wall-clock, 5 runs × 20 gold queries = 100 samples
  per mode. First run per query is discarded (warm-up). Reported as p50,
  p95, and mean.
- **Recall@10**: gold queries are tagged with one of the 10 seed topics.
  A returned document "hits" if its topic label (recorded in
  `topic_map.txt` by `seed.py`) matches the gold topic. Recall = hits / 10.

## Caveats

- Recall is a regression signal, not a research-grade eval. The corpus and
  gold set are synthetic and small.
- The cross-topic phrase injection in `seed.py` deliberately makes pure-BM25
  weaker than vector or RRF — this is by design so the scaffold can detect
  if one mode collapses to another.
- ParadeDB-on-PG17 image is pinned; `:latest` is now Postgres 18 with
  incompatible volume layout (see commit history).

## Files

| File | Purpose |
|---|---|
| `schema.sql` | Creates `bench_docs`, BM25 index, HNSW index |
| `seed.py` | Generates corpus, embeds, bulk-inserts, writes `topic_map.txt` |
| `queries.sql` | Reference SQL for the three retrieval modes |
| `harness.py` | Runs all three modes, writes `baseline-results.json` |
| `topic_map.txt` | id → topic mapping (output of seed.py) |
| `baseline-results.json` | Latency + recall numbers (output of harness.py) |
