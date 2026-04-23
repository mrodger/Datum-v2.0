FROM python:3.12-slim

WORKDIR /app

# Minimal build deps only — no Node.js, no Claude CLI, no MCP servers
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Non-root user (UID 1000 to match host volume ownership)
RUN groupadd -g 1000 appuser && useradd -u 1000 -g 1000 -d /home/appuser -m appuser \
    && mkdir -p /app/data /app/files \
    && chown -R appuser:appuser /app /home/appuser

ENV PYTHONUNBUFFERED=1
ENV PORT=8120
ENV HOST=0.0.0.0
ENV DB_PATH=/app/data/belle.db
ENV FILES_DIR=/app/files
ENV SYSTEM_PROMPT_PATH=/app/instances/belle/system_prompt.txt
ENV OPENROUTER_MODEL=anthropic/claude-sonnet-4-6

USER appuser

EXPOSE 8120

CMD ["sh", "-c", "uvicorn server:app --host 0.0.0.0 --port ${PORT:-8120} --no-server-header"]
