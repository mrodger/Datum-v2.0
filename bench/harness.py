"""
bench/harness.py — Run BM25 / vector / RRF fusion benchmarks against bench_docs.

For each retrieval mode:
  - Runs all 20 gold queries 5 times (warm-up discarded), totalling 100 calls
  - Measures per-call latency in ms
  - Computes recall@10 against the gold topic label

Writes baseline-results.json next to this script.

Run:
    python bench/harness.py
"""
from __future__ import annotations

import json
import os
import statistics
import time
from pathlib import Path

import psycopg2
import psycopg2.extras
from sentence_transformers import SentenceTransformer

DB_DSN = os.environ.get(
    "BENCH_DSN",
    "postgresql://mymir:mymir@localhost:5432/mymir",
)
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
TOP_K = 10
RRF_K = 60
RUNS_PER_QUERY = 5
WARMUPS = 1  # first run discarded

# Gold queries: (query_text, topic_label). Topic label must match
# one of the TOPICS keys in seed.py.
GOLD_QUERIES: list[tuple[str, str]] = [
    ("how does HNSW work", "vector_search"),
    ("BM25 saturation parameter", "bm25"),
    ("reciprocal rank fusion explained", "rrf"),
    ("MVCC tuple visibility postgres", "postgres"),
    ("retrieval augmented generation chunk size", "rag"),
    ("cgroups v2 hierarchy linux", "linux"),
    ("PostGIS spatial index types", "geospatial"),
    ("BBR vs CUBIC congestion control", "networking"),
    ("FlashAttention transformer optimisation", "ml"),
    ("blue green deployment rollout", "ops"),
    ("approximate nearest neighbour recall tradeoffs", "vector_search"),
    ("inverted index posting list compression", "bm25"),
    ("weighted rank fusion combSUM", "rrf"),
    ("partitioning strategies for large tables", "postgres"),
    ("HyDE hypothetical document embeddings", "rag"),
    ("eBPF XDP fast path packet processing", "networking"),
    ("LoRA adapter fine tuning", "ml"),
    ("circuit breaker and exponential backoff", "ops"),
    ("vector tiles MVT pyramid", "geospatial"),
    ("epoll edge triggered IO", "linux"),
]

BM25_SQL = """
SELECT id
FROM bench_docs
WHERE id @@@ paradedb.match('body', %s)
ORDER BY paradedb.score(id) DESC
LIMIT %s
"""

VECTOR_SQL = """
SELECT id
FROM bench_docs
ORDER BY embedding <=> %s::vector
LIMIT %s
"""

RRF_SQL = """
WITH bm AS (
    SELECT id, row_number() OVER (ORDER BY paradedb.score(id) DESC) AS r
    FROM bench_docs
    WHERE id @@@ paradedb.match('body', %s)
    LIMIT 50
),
vec AS (
    SELECT id, row_number() OVER (ORDER BY embedding <=> %s::vector) AS r
    FROM (
        SELECT id, embedding FROM bench_docs
        ORDER BY embedding <=> %s::vector LIMIT 50
    ) s
)
SELECT id
FROM (
    SELECT id, SUM(1.0 / (%s + r)) AS rrf_score FROM (
        SELECT id, r FROM bm UNION ALL SELECT id, r FROM vec
    ) u
    GROUP BY id
) f
ORDER BY rrf_score DESC
LIMIT %s
"""


def load_topic_map() -> dict[int, str]:
    """id -> topic_label, written by seed.py."""
    p = Path(__file__).parent / "topic_map.txt"
    out: dict[int, str] = {}
    for line in p.read_text().strip().splitlines():
        sid, topic = line.split("\t")
        out[int(sid)] = topic
    return out


def vec_literal(embedding) -> str:
    return "[" + ",".join(f"{float(x):.6f}" for x in embedding) + "]"


def run_mode(name: str, cur, topic_map: dict[int, str], embeddings) -> dict:
    latencies_ms: list[float] = []
    recalls: list[float] = []

    for qi, (query, gold_topic) in enumerate(GOLD_QUERIES):
        emb = vec_literal(embeddings[qi])
        for run in range(RUNS_PER_QUERY):
            t0 = time.perf_counter()
            if name == "bm25":
                cur.execute(BM25_SQL, (query, TOP_K))
            elif name == "vector":
                cur.execute(VECTOR_SQL, (emb, TOP_K))
            elif name == "rrf":
                cur.execute(RRF_SQL, (query, emb, emb, RRF_K, TOP_K))
            else:
                raise ValueError(name)
            rows = cur.fetchall()
            dt = (time.perf_counter() - t0) * 1000.0
            if run >= WARMUPS:
                latencies_ms.append(dt)
        # recall@k on the last run's ids
        ids = [r[0] for r in rows]
        hits = sum(1 for i in ids if topic_map.get(i) == gold_topic)
        recalls.append(hits / TOP_K)

    latencies_ms.sort()
    return {
        "n_calls_timed": len(latencies_ms),
        "latency_ms_p50": statistics.median(latencies_ms),
        "latency_ms_p95": latencies_ms[int(len(latencies_ms) * 0.95)],
        "latency_ms_mean": statistics.mean(latencies_ms),
        "recall_at_10_mean": statistics.mean(recalls),
        "recall_at_10_min": min(recalls),
    }


def main() -> int:
    print(f"Loading embedding model {MODEL_NAME}...")
    model = SentenceTransformer(MODEL_NAME)
    query_texts = [q for q, _ in GOLD_QUERIES]
    print(f"Embedding {len(query_texts)} gold queries...")
    query_embs = model.encode(query_texts, batch_size=32, convert_to_numpy=True)

    print(f"Connecting to {DB_DSN}...")
    conn = psycopg2.connect(DB_DSN)
    cur = conn.cursor()

    cur.execute("SELECT count(*) FROM bench_docs;")
    (n_docs,) = cur.fetchone()
    print(f"bench_docs row count: {n_docs}")

    topic_map = load_topic_map()
    print(f"topic_map entries: {len(topic_map)}")

    results = {}
    for mode in ("bm25", "vector", "rrf"):
        print(f"\n--- mode: {mode} ---")
        results[mode] = run_mode(mode, cur, topic_map, query_embs)
        for k, v in results[mode].items():
            print(f"  {k}: {v}")

    out_path = Path(__file__).parent / "baseline-results.json"
    out_path.write_text(
        json.dumps(
            {
                "n_docs": n_docs,
                "n_gold_queries": len(GOLD_QUERIES),
                "top_k": TOP_K,
                "rrf_k": RRF_K,
                "runs_per_query": RUNS_PER_QUERY,
                "warmups_discarded": WARMUPS,
                "results": results,
            },
            indent=2,
        )
    )
    print(f"\nWrote {out_path}")

    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
