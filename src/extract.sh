#!/usr/bin/env bash
# ============================================================
# extract.sh — Pull procedure definitions from PostgreSQL
# ============================================================
# Requires: psql (PostgreSQL 14+ client) on PATH
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
OUTPUT_SUBDIR="${OUTPUT_SUBDIR:-procedures}"
OUTPUT_DIR="${REPO_DIR}/${OUTPUT_SUBDIR}"
PSQL="${PSQL:-psql}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)       PGHOST="$2"; shift 2 ;;
        --port)       PGPORT="$2"; shift 2 ;;
        --database)   DATABASE="$2"; shift 2 ;;
        --username)   USERNAME="$2"; shift 2 ;;
        --schema)     SCHEMA="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --psql)       PSQL="$2"; shift 2 ;;
        -h|--help)    sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

TRACKED_PROCEDURES="${TRACKED_PROCEDURES:-tsa_sp_school_weight_cal,tsa_sp_school_weight_cav_cal,tsa_sp_student_weight_cal}"
IFS=',' read -r -a PROCEDURES <<< "$TRACKED_PROCEDURES"

# --- Pre-flight ---------------------------------------------------------
if [[ -z "${PGPASSWORD:-}" ]]; then
    echo "ERROR: PGPASSWORD environment variable is not set. Aborting." >&2
    exit 2
fi

if ! command -v "$PSQL" >/dev/null 2>&1; then
    echo "ERROR: psql client not found (looked for '$PSQL'). Install postgresql-client or pass --psql." >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR"

PSQL_BASE=(
    "--host=$PGHOST"
    "--port=$PGPORT"
    "--dbname=$DATABASE"
    "--username=$USERNAME"
    "--no-psqlrc"
    "--no-password"
    "-v" "ON_ERROR_STOP=1"
)

# --- Connectivity check -------------------------------------------------
if ! "$PSQL" "${PSQL_BASE[@]}" -A -t -c "SELECT 1" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to ${PGHOST}:${PGPORT}/${DATABASE} as ${USERNAME}." >&2
    exit 3
fi

# --- Helpers ------------------------------------------------------------
sanitize_for_filename() {
    local s="$1"
    s="$(printf '%s' "$s" | tr -c 'A-Za-z0-9._-' '_' | sed -e 's/__*/_/g' -e 's/^_//' -e 's/_$//')"
    [[ -z "$s" ]] && s="noargs"
    printf '%s' "$s"
}

FIELD_SEP="$(printf '\037')"
RECORD_SEP="$(printf '\036')"

invoke_psql_tuples() {
    "$PSQL" "${PSQL_BASE[@]}" -A -t -F "$FIELD_SEP" -R "$RECORD_SEP" -c "$1"
}

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %z')"
FAILURES=0

for sp in "${PROCEDURES[@]}"; do
    set +e
    list_out="$(invoke_psql_tuples \
"SELECT p.oid::text,
       pg_get_function_identity_arguments(p.oid),
       p.prokind
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = '${SCHEMA}'
  AND p.proname = '${sp}'
ORDER BY p.oid")"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "ERROR: Failed to list overloads for ${SCHEMA}.${sp}" >&2
        FAILURES=$((FAILURES+1))
        continue
    fi

    if [[ -z "${list_out//[[:space:]]/}" ]]; then
        echo "WARNING: Not found: ${SCHEMA}.${sp}" >&2
        continue
    fi

    IFS="$RECORD_SEP" read -r -d '' -a rows <<< "$list_out$RECORD_SEP" || true
    filtered_rows=()
    for r in "${rows[@]}"; do
        [[ -n "${r//[[:space:]]/}" ]] && filtered_rows+=("$r")
    done
    rows=("${filtered_rows[@]}")

    multi_overload=0
    [[ ${#rows[@]} -gt 1 ]] && multi_overload=1

    for row in "${rows[@]}"; do
        IFS="$FIELD_SEP" read -r oid arg_sig kind <<< "$row"
        oid="${oid//[$'\t\r\n ']/}"
        kind="${kind//[$'\t\r\n ']/}"

        set +e
        def="$(invoke_psql_tuples "SELECT pg_get_functiondef(${oid})")"
        rc=$?
        set -e
        if [[ $rc -ne 0 ]]; then
            echo "ERROR: pg_get_functiondef failed for oid ${oid}" >&2
            FAILURES=$((FAILURES+1))
            continue
        fi

        def="${def//$RECORD_SEP/}"
        def="${def//$'\r'/}"
        while [[ "$def" == *$'\n' || "$def" == *' ' || "$def" == *$'\t' ]]; do
            def="${def%$'\n'}"; def="${def% }"; def="${def%$'\t'}"
        done
        def="${def}"$'\n'

        case "$kind" in
            p) kind_label="PROCEDURE" ;;
            f) kind_label="FUNCTION"  ;;
            a) kind_label="AGGREGATE" ;;
            w) kind_label="WINDOW"    ;;
            *) kind_label="ROUTINE"   ;;
        esac

        header="-- ============================================================
-- source : ${SCHEMA}.${sp}(${arg_sig})
-- kind   : ${kind_label}
-- ============================================================
"

        if [[ $multi_overload -eq 1 ]]; then
            sanitized="$(sanitize_for_filename "$arg_sig")"
            file_name="${SCHEMA}.${sp}(${sanitized}).sql"
        else
            file_name="${SCHEMA}.${sp}.sql"
        fi
        file_path="${OUTPUT_DIR}/${file_name}"

        printf '%s%s' "$header" "$def" > "$file_path"
        echo "Extracted: $file_name"
    done
done

if [[ $FAILURES -gt 0 ]]; then
    echo "ERROR: $FAILURES procedure(s) failed to extract at $TIMESTAMP" >&2
    exit 1
fi

echo "Done at $TIMESTAMP"
