#!/usr/bin/env bash
# ============================================================
# setup.sh — One-time repo initialization for sp-tracker
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REMOTE_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-dir)   REPO_DIR="$2"; shift 2 ;;
        --remote-url) REMOTE_URL="$2"; shift 2 ;;
        -h|--help)    sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$REPO_DIR"

mkdir -p procedures logs

if [[ ! -f sp-tracker.conf ]]; then
cat > sp-tracker.conf <<'EOF'
# Shared configuration for the sp-tracker scripts.
# Edit values here instead of changing the scripts directly.

PGHOST="127.0.0.1"
PGPORT="21521"
DATABASE="bca_dev"
USERNAME="polaruser1"
SCHEMA="tsadba"
PSQL="psql"

BRANCH="main"
REMOTE="origin"
COMMIT_USER="sp-tracker-bot"
COMMIT_EMAIL="sp-tracker@localhost"

OUTPUT_SUBDIR="procedures"
LOG_SUBDIR="logs"
CRON_TIME="08:00"
TRACKED_PROCEDURES="tsa_sp_school_weight_cal,tsa_sp_school_weight_cav_cal,tsa_sp_student_weight_cal"
EOF
fi

if [[ ! -d .git ]]; then
    git init -b main >/dev/null
    echo "Initialized git repository."
else
    echo "Git repository already initialized."
fi

git config core.autocrlf false

cat > .gitignore <<'EOF'
# sp-tracker
logs/
*.log
secret.pgpass
*.bak
EOF

cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.sql text eol=lf
*.sh  text eol=lf
EOF

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
    2. Create ./secret.pgpass containing the DB password (one line); chmod 600 it.
    3. export PGPASSWORD="\$(cat ./secret.pgpass)"
    4. ./src/extract.sh        # validate
    5. ./src/sync.sh           # full cycle
    6. ./src/register-task.sh  # install daily cron entry
EOF
