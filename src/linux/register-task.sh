#!/usr/bin/env bash
# ============================================================
# register-task.sh — Install the daily sync as a cron entry
# ============================================================
# NOTE on PGPASSWORD:
#   cron does NOT inherit your shell's env vars. Either:
#     (a) place a `secret.pgpass` file at the repo root (gitignored), or
#     (b) export PGPASSWORD via the user's crontab, e.g.:
#           PGPASSWORD=...
#   Option (a) is the recommended default.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/sync.sh"
RUN_HOUR="08"
RUN_MIN="00"
TAG="# sp-tracker-sync"
REMOVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --time)   IFS=":" read -r RUN_HOUR RUN_MIN <<< "$2"; shift 2 ;;
        --remove) REMOVE=1; shift ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -f "$SYNC_SCRIPT" ]]; then
    echo "ERROR: sync.sh not found at $SYNC_SCRIPT" >&2
    exit 1
fi
chmod +x "$SYNC_SCRIPT" 2>/dev/null || true

existing="$(crontab -l 2>/dev/null | grep -vF "$TAG" || true)"

if [[ "$REMOVE" -eq 1 ]]; then
    printf '%s\n' "$existing" | crontab -
    echo "Removed sp-tracker cron entry."
    exit 0
fi

new_line="${RUN_MIN} ${RUN_HOUR} * * * /usr/bin/env bash ${SYNC_SCRIPT} >> ${SCRIPT_DIR}/../../logs/cron.log 2>&1 ${TAG}"

{
    [[ -n "$existing" ]] && printf '%s\n' "$existing"
    printf '%s\n' "$new_line"
} | crontab -

echo "Installed cron entry (daily at ${RUN_HOUR}:${RUN_MIN}):"
echo "  $new_line"
echo "Verify with: crontab -l"
