#!/usr/bin/env python3
"""
Backfill memory.agents / memory.conversations / memory.messages from the
datum-ui Postgres on vm107 (db=datum, tables datum_conversations + datum_messages)
into the Mymir ParadeDB on .102 (db=mymir, schema=memory).

Idempotent: refuses to run if memory.messages is non-empty unless --force,
in which case it TRUNCATEs the entire memory schema and reloads.

Source creds: VM107_DB_PASS from environment.
Target creds: mymir/mymir/mymir (docker-compose default; dev-only).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict

import psycopg2
import psycopg2.extras

SRC_DSN = dict(
    host="192.168.88.107",
    port=5432,
    dbname="datum",
    user="datum_remote",
)
DST_DSN = dict(
    host="127.0.0.1",
    port=5432,
    dbname="mymir",
    user="mymir",
    password="mymir",
)
TENANT_ID = 1
BATCH_SIZE = 500

MEMORY_TABLES = [
    "claim_embeddings",
    "claim_relations",
    "claim_mentions",
    "claims",
    "working_memory_items",
    "consolidation_jobs",
    "procedure_embeddings",
    "procedure_steps",
    "procedures",
    "episode_messages",
    "episodes",
    "messages",
    "conversations",
    "agents",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Truncate memory.* and reload even if non-empty.",
    )
    args = parser.parse_args()

    src_pw = os.environ.get("VM107_DB_PASS")
    if not src_pw:
        print("error: VM107_DB_PASS not set", file=sys.stderr)
        return 2

    src = psycopg2.connect(password=src_pw, **SRC_DSN)
    dst = psycopg2.connect(**DST_DSN)
    src.set_session(readonly=True)
    dst.autocommit = False

    try:
        with dst.cursor() as cur:
            cur.execute("SELECT count(*) FROM memory.messages")
            existing = cur.fetchone()[0]
            if existing > 0 and not args.force:
                print(
                    f"refusing: memory.messages has {existing} rows. "
                    "Pass --force to truncate-and-reload.",
                    file=sys.stderr,
                )
                return 3

            if args.force:
                cur.execute(
                    "TRUNCATE memory."
                    + ", memory.".join(MEMORY_TABLES)
                    + " RESTART IDENTITY CASCADE"
                )
                print(f"truncated memory.{{{','.join(MEMORY_TABLES)}}}")

        # --- agents ---
        with src.cursor() as scur:
            scur.execute("SELECT DISTINCT persona FROM datum_conversations ORDER BY persona")
            personas = [r[0] for r in scur.fetchall()]
        persona_to_agent: dict[str, int] = {}
        with dst.cursor() as cur:
            for p in personas:
                cur.execute(
                    "INSERT INTO memory.agents (tenant_id, name) "
                    "VALUES (%s, %s) RETURNING agent_id",
                    (TENANT_ID, p),
                )
                persona_to_agent[p] = cur.fetchone()[0]
        print(f"agents: {len(persona_to_agent)} inserted")

        # --- conversations ---
        with src.cursor(name="src_convs") as scur:
            scur.execute(
                "SELECT id, persona, title, cc_session_id, created_at, updated_at "
                "FROM datum_conversations ORDER BY created_at"
            )
            rows = scur.fetchall()
        src_id_to_conv: dict[str, int] = {}
        with dst.cursor() as cur:
            for src_id, persona, title, cc_sid, c_at, u_at in rows:
                cur.execute(
                    """
                    INSERT INTO memory.conversations
                        (tenant_id, agent_id, external_thread_id, title,
                         started_at, ended_at, metadata)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING conversation_id
                    """,
                    (
                        TENANT_ID,
                        persona_to_agent[persona],
                        src_id,
                        title,
                        c_at,
                        u_at,
                        psycopg2.extras.Json({"cc_session_id": cc_sid}),
                    ),
                )
                src_id_to_conv[src_id] = cur.fetchone()[0]
        print(f"conversations: {len(src_id_to_conv)} inserted")

        # --- messages ---
        # Stream from source ordered for deterministic turn_index per conversation.
        with src.cursor(name="src_msgs") as scur:
            scur.itersize = 2000
            scur.execute(
                """
                SELECT id, conversation_id, role, content, tool_calls,
                       input_tokens, output_tokens, cost_usd,
                       (embedding IS NOT NULL) AS has_embedding,
                       created_at
                FROM datum_messages
                ORDER BY conversation_id, created_at, id
                """
            )
            turn_idx: dict[int, int] = defaultdict(int)
            buf: list[tuple] = []
            total = 0
            with dst.cursor() as dcur:
                for src_id, conv_src_id, role, content, tool_calls, in_tok, out_tok, cost, has_emb, c_at in scur:
                    conv_id = src_id_to_conv.get(conv_src_id)
                    if conv_id is None:
                        # orphan message — skip with a note
                        continue
                    if in_tok is None and out_tok is None:
                        token_count = None
                    else:
                        token_count = (in_tok or 0) + (out_tok or 0)
                    md = {
                        "tool_calls": tool_calls,
                        "cost_usd": float(cost) if cost is not None else None,
                        "source_id": src_id,
                        "has_embedding": has_emb,
                    }
                    idx = turn_idx[conv_id]
                    turn_idx[conv_id] = idx + 1
                    buf.append(
                        (
                            TENANT_ID,
                            conv_id,
                            role,
                            idx,
                            content,
                            token_count,
                            c_at,
                            src_id,
                            psycopg2.extras.Json(md),
                        )
                    )
                    if len(buf) >= BATCH_SIZE:
                        psycopg2.extras.execute_values(
                            dcur,
                            """
                            INSERT INTO memory.messages
                                (tenant_id, conversation_id, role, turn_index,
                                 content, token_count, created_at,
                                 source_message_id, metadata)
                            VALUES %s
                            """,
                            buf,
                        )
                        total += len(buf)
                        buf = []
                if buf:
                    psycopg2.extras.execute_values(
                        dcur,
                        """
                        INSERT INTO memory.messages
                            (tenant_id, conversation_id, role, turn_index,
                             content, token_count, created_at,
                             source_message_id, metadata)
                        VALUES %s
                        """,
                        buf,
                    )
                    total += len(buf)
        print(f"messages: {total} inserted")

        dst.commit()
        print("commit ok")
        return 0
    except Exception:
        dst.rollback()
        raise
    finally:
        src.close()
        dst.close()


if __name__ == "__main__":
    sys.exit(main())
