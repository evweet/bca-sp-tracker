#!/usr/bin/env bash
# ============================================================
# setup.sh — One-time repo initialization for sp-tracker
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REMOTE_URL=""

cd "$REPO_DIR"

mkdir -p procedures logs

if [[ ! -f sp-tracker.conf ]]; then
    echo "ERROR: sp-tracker.conf not found. Please create it with appropriate settings before running this script." >&2
    exit 2
fi

if [[ ! -d .git ]]; then
    git init -b main >/dev/null
    echo "Initialized git repository."
else
    echo "Git repository already initialized."
fi

git config core.autocrlf false

git add -A  2>/dev/null || true
if [[ -n "$(git status --porcelain)" ]]; then
    git commit -m "chore: initial sp-tracker setup" >/dev/null
    echo "Created initial commit."
else
    echo "Nothing new to commit."
fi

if [[ -n "$REMOTE_URL" ]]; then
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
        echo "Updated origin -> $REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
        echo "Added origin -> $REMOTE_URL"
    fi
    echo "Push with: git push -u origin main"
fi

chmod +x "${SCRIPT_DIR}"/*.sh

cat <<EOF

Next steps (run from repo root '${REPO_DIR}'):
    1. Edit ./sp-tracker.conf to change database, branch, paths, cron time, or tracked procedures.
    2. Create ./secret.pgpass containing the DB password (one line).
    3. ./src/sync.sh           # full cycle
    4. ./src/register-task.sh  # install daily cron entry
EOF
