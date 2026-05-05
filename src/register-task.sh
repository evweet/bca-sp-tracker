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

SYNC_SCRIPT="${SCRIPT_DIR}/sync.sh"
CRON_TIME="${CRON_TIME:-08:00}"
IFS=":" read -r RUN_HOUR RUN_MIN <<< "$CRON_TIME"
LOG_SUBDIR="${LOG_SUBDIR:-logs}"
TAG="# sp-tracker-sync"
REMOVE=0

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

new_line="${RUN_MIN} ${RUN_HOUR} * * * /usr/bin/env bash ${SYNC_SCRIPT} >> ${REPO_DIR}/${LOG_SUBDIR}/cron.log 2>&1 ${TAG}"

{
    [[ -n "$existing" ]] && printf '%s\n' "$existing"
    printf '%s\n' "$new_line"
} | crontab -

echo "Installed cron entry (daily at ${RUN_HOUR}:${RUN_MIN}):"
echo "  $new_line"
echo "Verify with: crontab -l"
