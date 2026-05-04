#!/usr/bin/env bash
# ============================================================
# sync.sh — Detect PG procedure changes and commit/push to Git
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_DIR}/sp-tracker.conf"

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
        set +a
    fi
}

load_config

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-21521}"
DATABASE="${DATABASE:-bca_dev}"
USERNAME="${USERNAME:-polaruser1}"
SCHEMA="${SCHEMA:-tsadba}"
BRANCH="${BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
COMMIT_USER="${COMMIT_USER:-sp-tracker-bot}"
COMMIT_EMAIL="${COMMIT_EMAIL:-sp-tracker@localhost}"
OUTPUT_SUBDIR="${OUTPUT_SUBDIR:-procedures}"
LOG_SUBDIR="${LOG_SUBDIR:-logs}"
NO_PUSH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-dir)     REPO_DIR="$2"; shift 2 ;;
        --host)         PGHOST="$2"; shift 2 ;;
        --port)         PGPORT="$2"; shift 2 ;;
        --database)     DATABASE="$2"; shift 2 ;;
        --username)     USERNAME="$2"; shift 2 ;;
        --schema)       SCHEMA="$2"; shift 2 ;;
        --branch)       BRANCH="$2"; shift 2 ;;
        --remote)       REMOTE="$2"; shift 2 ;;
        --commit-user)  COMMIT_USER="$2"; shift 2 ;;
        --commit-email) COMMIT_EMAIL="$2"; shift 2 ;;
        --no-push)      NO_PUSH=1; shift ;;
        -h|--help)      sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$REPO_DIR"

LOG_DIR="${REPO_DIR}/${LOG_SUBDIR}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/sync-$(date '+%Y%m%d').log"
exec > >(tee -a "$LOG_FILE") 2>&1

started_at="$(date '+%Y-%m-%d %H:%M:%S %z')"
echo "=== sp-tracker sync @ ${started_at} ==="

if [[ -z "${PGPASSWORD:-}" ]]; then
    secret_file="${REPO_DIR}/secret.pgpass"
    if [[ -f "$secret_file" ]]; then
        PGPASSWORD="$(sed -e 's/[[:space:]]*$//' "$secret_file" | grep -m1 -v '^[[:space:]]*$' || true)"
        export PGPASSWORD
        echo "Loaded PGPASSWORD from secret.pgpass"
    else
        echo "ERROR: PGPASSWORD not set and secret.pgpass not found. Aborting." >&2
        exit 2
    fi
fi

echo "Extracting procedures from ${SCHEMA}..."
"${SCRIPT_DIR}/extract.sh" \
    --host "$PGHOST" --port "$PGPORT" --database "$DATABASE" \
    --username "$USERNAME" --schema "$SCHEMA" \
    --output-dir "${REPO_DIR}/${OUTPUT_SUBDIR}"

status="$(git status --porcelain -- "${OUTPUT_SUBDIR}/")"
if [[ -z "$status" ]]; then
    echo "No changes detected. Nothing to commit."
    exit 0
fi
echo "Changes detected:"
echo "$status"

git config user.name  "$COMMIT_USER"
git config user.email "$COMMIT_EMAIL"

git add "${OUTPUT_SUBDIR}/"

timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
msg_file="$(mktemp)"
{
    echo "chore(sp): snapshot ${SCHEMA} @ ${timestamp}"
    echo
    echo "Changed files:"
    echo "$status"
} > "$msg_file"

git commit -F "$msg_file"
rm -f "$msg_file"

if [[ $NO_PUSH -eq 1 ]]; then
    echo "Skipping push (--no-push set)."
    exit 0
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "WARNING: Remote '$REMOTE' not configured. Commit kept locally." >&2
    exit 0
fi

git push "$REMOTE" "$BRANCH"
echo "Pushed changes to ${REMOTE}/${BRANCH}"
