"""Codex Bridge proxy — drop-in replacement for belle-openrouter agent.py.

Implements the same run_agent() interface so server.py works unchanged.
Proxies all requests to the Codex bridge service (Part C).

Event flow:
  bridge SSE → agent.py (filter/normalize) → server.py (persist + final done) → frontend

The bridge emits: text, tool_use, done, error events (already normalized by Part C parser).
This agent passes text/tool_use/error through. Bridge 'done' events are ABSORBED (not yielded)
because server.py emits its own authoritative 'done' in its finally block. Yielding bridge done
would cause a double-done bug where the second done (from server, no cost_usd) overwrites the
frontend's costUsd variable with undefined.
"""
import json
import logging
import os
from pathlib import Path
from typing import AsyncGenerator

import httpx

log = logging.getLogger("codex-agent")

DEFAULT_MODEL: str = os.environ.get("DEFAULT_MODEL", "gpt-5.4")
BRIDGE_URL: str = os.environ.get("CODEX_BRIDGE_URL", "http://host.docker.internal:8092")
BRIDGE_TOKEN: str = os.environ.get("CODEX_BRIDGE_TOKEN", "")
SYSTEM_PROMPT_PATH: str = os.environ.get(
    "SYSTEM_PROMPT_PATH", "/app/instances/codex/system_prompt.txt"
)

ALLOWED_MODELS: set[str] = {
    "gpt-5.4", "gpt-5.4-mini", "codex-5.4",
    "gpt-4o", "gpt-4o-mini", "default",
}

def _load_system_prompt() -> str:
    try:
        return Path(SYSTEM_PROMPT_PATH).read_text().strip()
    except Exception:
        return ""

def _build_messages(messages, memory_context, history):
    bridge_messages = []
    sys_prompt = _load_system_prompt()
    if sys_prompt:
        bridge_messages.append({"role": "system", "content": sys_prompt})
    if memory_context:
        bridge_messages.append({"role": "system", "content": f"Memory:\n{memory_context}"})
    if history:
        bridge_messages.extend(history)
        if messages:
            last_hist = history[-1] if history else {}
            last_msg = messages[-1] if messages else {}
            if last_hist.get("content") != last_msg.get("content"):
                bridge_messages.extend(messages)
    else:
        bridge_messages.extend(messages)
    return bridge_messages

async def run_agent(
    messages: list,
    model: str = "default",
    conversation_id: str = None,
    memory_context: str = "",
    history: list = None,
    cc_session_id: str = None,
) -> AsyncGenerator[dict, None]:
    effective_model = model if model in ALLOWED_MODELS and model != "default" else DEFAULT_MODEL
    bridge_messages = _build_messages(messages, memory_context, history)
    headers = {"Content-Type": "application/json"}
    if BRIDGE_TOKEN:
        headers["Authorization"] = f"Bearer {BRIDGE_TOKEN}"
    try:
        async with httpx.AsyncClient(timeout=660.0) as client:
            async with client.stream(
                "POST", f"{BRIDGE_URL}/chat", headers=headers,
                json={"messages": bridge_messages, "model": effective_model},
            ) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    yield {"type": "error", "detail": f"bridge {response.status_code}: {body.decode()[:200]}"}
                    return
                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    try:
                        event = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue
                    etype = event.get("type", "")
                    if etype in ("text", "tool_use", "error"):
                        yield event
                    elif etype == "done":
                        cost = event.get("cost_usd", 0)
                        if cost:
                            log.info("bridge done: cost=$%.4f", cost)
    except httpx.ConnectError:
        yield {"type": "error", "detail": "Codex bridge unreachable — is it running on :8092?"}
    except httpx.ReadTimeout:
        yield {"type": "error", "detail": "Codex bridge timed out (660s)."}
    except Exception as e:
        yield {"type": "error", "detail": f"codex-bridge error: {e}"}
