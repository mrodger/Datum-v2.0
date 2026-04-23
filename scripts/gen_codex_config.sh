#!/usr/bin/env bash
# Outputs .codex/config.toml — Codex project configuration
cat << 'EOF'
# Codex project configuration for Datum backup drone
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.auto]
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.mini]
model = "gpt-5.4-mini"
sandbox = "workspace-write"

[profiles.codex]
model = "codex-5.4"
sandbox = "workspace-write"
EOF
