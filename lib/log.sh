#!/usr/bin/env bash
# lib/log.sh — append-only error log under macOS' standard logs dir.
# Components call log_error when a feature fails so the dashboard line
# can stay short and the full stderr/output lives somewhere tail-able.

DASHBOARD_LOG_DIR="${HOME}/Library/Logs/cli-dashboard"
DASHBOARD_LOG_FILE="${DASHBOARD_LOG_DIR}/dashboard.log"

log_error() {
  local source="$1"; shift
  mkdir -p "$DASHBOARD_LOG_DIR"
  {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$source"
    printf '%s\n\n' "$*"
  } >>"$DASHBOARD_LOG_FILE"
}

# Pretty path for inline messages: ~/Library/Logs/cli-dashboard/dashboard.log
log_path_display() {
  printf '%s' "${DASHBOARD_LOG_FILE/#$HOME/~}"
}
