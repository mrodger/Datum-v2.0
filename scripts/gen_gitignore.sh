#!/usr/bin/env bash
# Outputs .gitignore
cat << 'EOF'
.env
*.codex-backup
bootstrap_report.md
workspace/
scratch/
memory/inbox/
memory/archive/
__pycache__/
*.pyc
.venv/
vault
memory/curated
EOF
