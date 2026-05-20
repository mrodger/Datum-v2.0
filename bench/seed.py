"""
bench/seed.py — Synthetic corpus generator for hybrid-retrieval benchmark.

Generates 1000 short documents across 10 topics, embeds with
sentence-transformers/all-MiniLM-L6-v2 (384-d, CPU), bulk-inserts into
bench_docs.

Run:
    python bench/seed.py
"""
from __future__ import annotations

import os
import random
import sys
from pathlib import Path

import psycopg2
import psycopg2.extras
from sentence_transformers import SentenceTransformer

DB_DSN = os.environ.get(
    "BENCH_DSN",
    "postgresql://mymir:mymir@localhost:5432/mymir",
)
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
N_DOCS = 1000
RNG_SEED = 42

TOPICS = {
    "postgres": [
        "Postgres WAL replication", "MVCC tuple visibility", "vacuum and bloat",
        "logical decoding", "btree vs GiST indexes", "partitioning strategies",
        "JSONB performance", "row-level security", "connection pooling with pgbouncer",
        "synchronous_commit tradeoffs",
    ],
    "vector_search": [
        "HNSW graph construction", "IVFFlat training and probes", "cosine vs L2 distance",
        "embedding model dimension tradeoffs", "approximate nearest neighbour recall",
        "vector quantisation", "hybrid sparse-dense retrieval",
        "filtering with pre vs post strategies", "MTEB benchmarks",
        "OpenAI text-embedding-3-small notes",
    ],
    "bm25": [
        "TF-IDF derivation", "BM25 saturation parameter k1", "length normalisation b",
        "inverted index posting lists", "Lucene scoring internals",
        "BM25F for fielded documents", "BM25L for long documents", "stopword removal",
        "stemming and lemmatisation", "query likelihood vs BM25",
    ],
    "rrf": [
        "reciprocal rank fusion", "weighted rank fusion", "CombSUM and CombMNZ",
        "Borda count voting", "rank aggregation theory", "fusion of dense and sparse",
        "k=60 default constant", "score normalisation issues",
        "learning to rank vs fusion", "ensemble retrieval architectures",
    ],
    "rag": [
        "retrieval augmented generation", "chunk size and overlap",
        "hierarchical retrieval", "parent document retrievers",
        "contextual compression", "query rewriting", "HyDE hypothetical documents",
        "MultiQueryRetriever", "self-query retrievers", "reranking with cross-encoders",
    ],
    "linux": [
        "cgroups v2 hierarchy", "namespaces and unshare", "epoll edge-triggered",
        "futex syscall", "io_uring", "sysctl networking knobs",
        "systemd unit dependencies", "udev rules", "audit subsystem", "ftrace and bpftrace",
    ],
    "geospatial": [
        "PostGIS SP-GiST indexes", "spatial reference systems", "EPSG transformations",
        "GeoJSON vs WKT", "spatial joins", "raster vs vector", "tile pyramids",
        "vector tiles MVT", "WGS84 vs NZTM2000", "kriging interpolation",
    ],
    "networking": [
        "TCP congestion control", "BBR vs CUBIC", "QUIC handshake", "MTU and PMTUD",
        "BGP route reflectors", "OSPF area design", "VXLAN encapsulation",
        "eBPF XDP fast path", "Linux qdisc fq_codel", "RDMA RoCE deployment",
    ],
    "ml": [
        "transformer attention complexity", "RoPE rotary embeddings",
        "GQA grouped query attention", "FlashAttention", "speculative decoding",
        "LoRA adapters", "quantisation int8 vs fp8", "mixture of experts",
        "RLHF reward models", "DPO direct preference optimisation",
    ],
    "ops": [
        "blue-green deployment", "canary rollouts", "feature flags",
        "circuit breakers", "exponential backoff", "idempotency keys",
        "outbox pattern", "saga choreography", "distributed tracing", "SLO error budgets",
    ],
}


def generate_doc(rng: random.Random, topic: str, prompts: list[str]) -> tuple[str, str]:
    title = rng.choice(prompts)
    other_topics = [t for t in TOPICS if t != topic]
    cross_topic = rng.choice(other_topics)
    cross_phrase = rng.choice(TOPICS[cross_topic])
    body = (
        f"{title}. This document discusses {title.lower()} in the context of {topic}. "
        f"It also briefly touches on {cross_phrase.lower()} as a related concept. "
        f"Key terms: {topic}, {', '.join(rng.sample(prompts, k=3))}. "
        f"See also {cross_phrase}."
    )
    return title, body


def main() -> int:
    rng = random.Random(RNG_SEED)
    print(f"Generating {N_DOCS} synthetic docs across {len(TOPICS)} topics...")
    docs: list[tuple[str, str, str]] = []
    per_topic = N_DOCS // len(TOPICS)
    for topic, prompts in TOPICS.items():
        for _ in range(per_topic):
            title, body = generate_doc(rng, topic, prompts)
            docs.append((topic, title, body))
    rng.shuffle(docs)

    print(f"Loading embedding model {MODEL_NAME}...")
    model = SentenceTransformer(MODEL_NAME)

    print(f"Embedding {len(docs)} documents (batch_size=64)...")
    bodies = [d[2] for d in docs]
    embeddings = model.encode(
        bodies, batch_size=64, show_progress_bar=True, convert_to_numpy=True
    )

    print(f"Connecting to {DB_DSN}...")
    conn = psycopg2.connect(DB_DSN)
    conn.autocommit = False
    cur = conn.cursor()

    print("Truncating bench_docs...")
    cur.execute("TRUNCATE bench_docs RESTART IDENTITY;")

    print("Bulk-inserting...")
    rows = [
        (title, body, "[" + ",".join(f"{x:.6f}" for x in emb) + "]")
        for (_, title, body), emb in zip(docs, embeddings)
    ]
    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO bench_docs (title, body, embedding) VALUES %s",
        rows,
        template="(%s, %s, %s::vector)",
        page_size=200,
    )
    conn.commit()
    cur.execute("SELECT count(*) FROM bench_docs;")
    (n,) = cur.fetchone()
    print(f"Inserted {n} rows.")

    # Also write a topic mapping so the harness can label gold queries.
    out = Path(__file__).parent / "topic_map.txt"
    out.write_text("\n".join(f"{i+1}\t{t}" for i, (t, _, _) in enumerate(docs)))
    print(f"Topic map written to {out}")

    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
