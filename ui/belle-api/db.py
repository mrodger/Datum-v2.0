"""SQLite schema for eDNA Insights."""
import sqlite3
import os
from pathlib import Path
from datetime import datetime, timezone

DB_PATH = Path(os.environ.get("DB_PATH", "/app/data/edna.db"))
MEMORY_MD_PATH = DB_PATH.parent / "memory.md"


def _now():
    return datetime.now(timezone.utc).isoformat()


def init_db():
    """Create schema."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()

        c.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT,
                cc_session_id TEXT,
                created_at TEXT,
                updated_at TEXT
            )
        """)
        # Migration: add column to existing DBs
        try:
            c.execute("ALTER TABLE conversations ADD COLUMN cc_session_id TEXT")
        except sqlite3.OperationalError:
            pass  # column already exists

        c.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT,
                created_at TEXT,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id)
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS memory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                category TEXT DEFAULT 'general',
                created_at TEXT,
                updated_at TEXT
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                path TEXT NOT NULL,
                content_type TEXT,
                summary TEXT,
                indexed_at TEXT
            )
        """)

        conn.commit()

    _sync_memory_md()


def _sync_memory_md():
    """Rebuild the markdown memory cache from SQLite."""
    try:
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute("SELECT key, value, category FROM memory ORDER BY category, key")
            rows = c.fetchall()
        if not rows:
            MEMORY_MD_PATH.write_text("")
            return
        lines = ["## Your Memory (persistent facts about this project)"]
        current_cat = None
        for key, value, category in rows:
            if category != current_cat:
                lines.append(f"\n### {category.title()}")
                current_cat = category
            lines.append(f"- **{key}**: {value}")
        MEMORY_MD_PATH.write_text("\n".join(lines))
    except Exception:
        pass


def log_message(conversation_id: str, role: str, content: str) -> None:
    now = _now()
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""
            INSERT OR IGNORE INTO conversations (id, created_at, updated_at)
            VALUES (?, ?, ?)
        """, (conversation_id, now, now))
        c.execute(
            "INSERT INTO messages (conversation_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            (conversation_id, role, content, now)
        )
        c.execute("UPDATE conversations SET updated_at = ? WHERE id = ?", (now, conversation_id))
        conn.commit()


def get_history(conversation_id: str) -> list:
    """Return message history for a conversation."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT role, content FROM messages WHERE conversation_id = ? ORDER BY created_at",
            (conversation_id,)
        )
        rows = c.fetchall()
    return [{"role": r[0], "content": r[1]} for r in rows]


def store_memory(key: str, value: str, category: str = "general") -> str:
    now = _now()
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM memory WHERE key = ?", (key,))
        existing = c.fetchone()
        if existing:
            c.execute(
                "UPDATE memory SET value = ?, category = ?, updated_at = ? WHERE key = ?",
                (value, category, now, key)
            )
            result = f"Memory updated: {key}"
        else:
            c.execute(
                "INSERT INTO memory (key, value, category, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                (key, value, category, now, now)
            )
            result = f"Memory stored: {key}"
        conn.commit()
    _sync_memory_md()
    return result


def recall_memory(query: str) -> str:
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute(
            "SELECT key, value, category FROM memory WHERE key LIKE ? OR value LIKE ? ORDER BY updated_at DESC LIMIT 10",
            (f"%{query}%", f"%{query}%")
        )
        rows = c.fetchall()
    if not rows:
        return "No matching memories found."
    return "\n".join(f"[{r[2]}] {r[0]}: {r[1]}" for r in rows)


def list_memory() -> list:
    """Return all memory entries as a list of dicts."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT key, value, category, updated_at FROM memory ORDER BY category, key")
        rows = c.fetchall()
    return [{"key": r[0], "value": r[1], "category": r[2], "updated_at": r[3]} for r in rows]


def delete_memory(key: str) -> bool:
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("DELETE FROM memory WHERE key = ?", (key,))
        deleted = c.rowcount > 0
        conn.commit()
    if deleted:
        _sync_memory_md()
    return deleted


def get_all_memory() -> str:
    """Return all memory entries from markdown cache (fast) or fall back to SQLite."""
    try:
        if MEMORY_MD_PATH.exists():
            return MEMORY_MD_PATH.read_text()
    except Exception:
        pass
    # Fallback: rebuild from SQLite
    _sync_memory_md()
    try:
        return MEMORY_MD_PATH.read_text() if MEMORY_MD_PATH.exists() else ""
    except Exception:
        return ""


def register_file(name: str, path: str, content_type: str, summary: str = None) -> None:
    now = _now()
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""
            INSERT OR REPLACE INTO files (name, path, content_type, summary, indexed_at)
            VALUES (?, ?, ?, ?, ?)
        """, (name, path, content_type, summary, now))
        conn.commit()


def list_recent_conversations(limit: int = 20) -> list:
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""
            SELECT c.id, c.title, c.created_at, c.updated_at,
                   (SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at LIMIT 1) as first_msg
            FROM conversations c
            ORDER BY c.updated_at DESC
            LIMIT ?
        """, (limit,))
        rows = c.fetchall()
    return [{"id": r[0], "title": r[1], "created_at": r[2], "updated_at": r[3], "preview": r[4]} for r in rows]


def set_conversation_title(conversation_id: str, title: str):
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            "UPDATE conversations SET title = ? WHERE id = ?",
            (title, conversation_id)
        )
        conn.commit()


def get_session_id(conversation_id: str) -> str | None:
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT cc_session_id FROM conversations WHERE id = ?", (conversation_id,))
        row = c.fetchone()
    return row[0] if row and row[0] else None


def set_session_id(conversation_id: str, session_id: str) -> None:
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            "UPDATE conversations SET cc_session_id = ? WHERE id = ?",
            (session_id, conversation_id)
        )
        conn.commit()
