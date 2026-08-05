#!/usr/bin/env bash
# ============================================================
# extract.sh — Pull schema definitions from PostgreSQL
# ============================================================
# Requires: pg_dump (PostgreSQL client) on PATH
# Auth:     password supplied via $PGPASSWORD (never logged)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_DIR}/sp-tracker.conf"

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        . <(sed 's/\r$//' "$CONFIG_FILE")
        set +a
    fi
}

load_config

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-21521}"
DATABASE="${DATABASE:-bca_dev}"
USERNAME="${USERNAME:-polaruser1}"
SCHEMA="${SCHEMA:-bcadb}"
PG_DUMP="${PG_DUMP:-pg_dump}"
OUTPUT_ROOT="${REPO_DIR}/schemas"

IFS=',' read -r -a DATABASES <<< "$DATABASE"

if [[ -z "${PGPASSWORD:-}" ]]; then
    echo "ERROR: PGPASSWORD environment variable is not set. Aborting." >&2
    exit 2
fi

if ! command -v "$PG_DUMP" >/dev/null 2>&1; then
    echo "ERROR: pg_dump client not found (looked for '$PG_DUMP'). Install postgresql-client or set PG_DUMP." >&2
    exit 2
fi

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

CURRENT_TEMP_FILE=""
cleanup_temp_file() {
    if [[ -n "$CURRENT_TEMP_FILE" ]]; then
        rm -f "$CURRENT_TEMP_FILE"
    fi
}
trap cleanup_temp_file EXIT INT TERM HUP

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %z')"
FAILURES=0

for database in "${DATABASES[@]}"; do
    database="$(trim_whitespace "$database")"
    if [[ -z "$database" ]]; then
        echo "WARNING: Skipping empty database entry." >&2
        continue
    fi

    OUTPUT_DIR="${OUTPUT_ROOT}/${database}"
    OUTPUT_FILE="${OUTPUT_DIR}/${SCHEMA}.sql"
    mkdir -p "$OUTPUT_DIR"
    TEMP_FILE="$(mktemp "${OUTPUT_DIR}/.${SCHEMA}.sql.tmp.XXXXXX")"
    CURRENT_TEMP_FILE="$TEMP_FILE"

    echo "Extracting schema ${SCHEMA} from database ${database}..."
    if "$PG_DUMP" \
        --schema-only \
        --no-owner \
        --no-privileges \
        --restrict-key=7cL3mQ9vN2xR8kT5pW4dF6hJ1sB0yGzA \
        "--host=$PGHOST" \
        "--port=$PGPORT" \
        "--username=$USERNAME" \
        "--schema=$SCHEMA" \
        "--dbname=$database" \
        "--file=$TEMP_FILE"; then
        mv "$TEMP_FILE" "$OUTPUT_FILE"
        CURRENT_TEMP_FILE=""
        echo "Extracted: ${database}/${SCHEMA}.sql"
    else
        rm -f "$TEMP_FILE"
        CURRENT_TEMP_FILE=""
        echo "ERROR: Failed to extract ${database}.${SCHEMA}" >&2
        FAILURES=$((FAILURES+1))
    fi
done

if [[ $FAILURES -gt 0 ]]; then
    echo "ERROR: $FAILURES schema dump(s) failed at $TIMESTAMP" >&2
    exit 1
fi

echo "Done at $TIMESTAMP"