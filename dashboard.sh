#!/usr/bin/env bash
# dashboard.sh — entry point. Validates requirements, then renders enabled
# components on a refresh loop.
#
# Refreshes run in the background: every component is fetched+rendered in its
# own subprocess while the previous frame stays on screen with a spinner in the
# status bar. The frame is swapped in one repaint once all of them are in, so
# the dashboard is never half-updated and never blank.

set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh
source "${DASHBOARD_DIR}/lib/ui.sh"
# shellcheck source=lib/log.sh
source "${DASHBOARD_DIR}/lib/log.sh"
# shellcheck source=config.sh
source "${DASHBOARD_DIR}/config.sh"
# shellcheck source=lib/refresh.sh
source "${DASHBOARD_DIR}/lib/refresh.sh"
# shellcheck source=lib/demo.sh
source "${DASHBOARD_DIR}/lib/demo.sh"
# shellcheck source=requirements.sh
source "${DASHBOARD_DIR}/requirements.sh"
# shellcheck source=components/brew/brew.sh
source "${DASHBOARD_DIR}/components/brew/brew.sh"
# shellcheck source=components/github/github.sh
source "${DASHBOARD_DIR}/components/github/github.sh"
# shellcheck source=components/jira/jira.sh
source "${DASHBOARD_DIR}/components/jira/jira.sh"
# shellcheck source=components/version/version.sh
source "${DASHBOARD_DIR}/components/version/version.sh"

# --- Frame state -------------------------------------------------------------
# What is currently on screen. Held across cycles so a refresh in flight can
# keep showing the last good frame.
DASHBOARD_FRAME=''            # body: every section, concatenated
DASHBOARD_VERSION=''          # version component's inline status-bar fragment
DASHBOARD_UPDATED_AT=''       # clock of the last completed refresh
DASHBOARD_FAILED=()           # component names that failed last cycle
DASHBOARD_TOTAL=0             # components in the last cycle
DASHBOARD_SHUTDOWN=false
DASHBOARD_SLEEP_PID=''

# Registry. Order here is the order sections appear on screen. Body components
# render a section; status components render inline into the status bar.
DASHBOARD_BODY=()
DASHBOARD_STATUS=()

dashboard_register_components() {
  DASHBOARD_BODY=()
  DASHBOARD_STATUS=()
  if config_enabled COMPONENT_BREW;    then DASHBOARD_BODY+=(brew:brew_render);        fi
  if config_enabled COMPONENT_GITHUB;  then DASHBOARD_BODY+=(github:github_render);    fi
  if config_enabled COMPONENT_JIRA;    then DASHBOARD_BODY+=(jira:jira_render);        fi
  if config_enabled COMPONENT_VERSION; then DASHBOARD_STATUS+=(version:version_render); fi
}

# --- Status bar --------------------------------------------------------------

# dashboard_failure_segment — nothing when the last cycle was clean, otherwise
# names the sources that failed and points at the log.
dashboard_failure_segment() {
  local failed=${#DASHBOARD_FAILED[@]} names='' name
  if (( failed == 0 )); then return 0; fi
  for name in "${DASHBOARD_FAILED[@]}"; do
    if [[ -n $names ]]; then names+=', '; fi
    names+="$name"
  done
  if (( failed >= DASHBOARD_TOTAL )); then
    printf '%s %s' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_KO" "all ${failed} sources failed")"
  else
    printf '%s %s' \
      "$(ui_paint "$UI_WARN" "$UI_ICON_WARN")" \
      "$(ui_paint "$UI_WARN" "${names} failed")"
  fi
}

# dashboard_status_line [<spinner> <done> <total>] — the top line, no trailing
# newline. Passing a spinner frame renders it as "refresh in flight".
dashboard_status_line() {
  local spinner="${1:-}" done_n="${2:-0}" total="${3:-0}"
  local segments=() segment line='' sep

  if [[ -n $spinner ]]; then
    segments+=("$(ui_paint "$UI_INFO" "${spinner} Refreshing ${done_n}/${total} sources")")
  fi
  segments+=("$(ui_paint "$UI_DIM$UI_MUTED" "Updated ${DASHBOARD_UPDATED_AT:-—}")")
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    segments+=("$(ui_paint "$UI_DIM$UI_MUTED" 'single render')")
  else
    segments+=("$(ui_paint "$UI_DIM$UI_MUTED" "refresh every ${DASHBOARD_REFRESH_MINUTES}m")")
  fi
  segment=$(dashboard_failure_segment)
  if [[ -n $segment ]]; then segments+=("$segment"); fi
  if [[ -n $DASHBOARD_VERSION ]]; then segments+=("$DASHBOARD_VERSION"); fi

  sep=" $(ui_paint "$UI_MUTED" '·') "
  for segment in "${segments[@]}"; do
    if [[ -n $line ]]; then line+="$sep"; fi
    line+="$segment"
  done
  printf '%s' "$line"
}

# --- Painting ----------------------------------------------------------------

# The status bar sits on line 1 of the frame while looping; in single-render
# mode it is just the line we are standing on.
dashboard_status_seek() {
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    printf '\r'
  else
    ui_cursor_home
  fi
}

# dashboard_paint_status <spinner> <done> <total> — rewrite the status bar in
# place. Cheap enough to animate, and it never touches the body below.
dashboard_paint_status() {
  if [[ ! -t 1 ]]; then return 0; fi
  dashboard_status_seek
  ui_line_erase
  printf '%s' "$(dashboard_status_line "$@")"
}

# dashboard_paint — repaint status bar + body from frame state.
dashboard_paint() {
  ui_screen_reset
  ui_line_erase
  printf '%s\n\n%s\n' "$(dashboard_status_line)" "$DASHBOARD_FRAME"
}

# --- Refresh cycle -----------------------------------------------------------

dashboard_spawn_refresh() {
  local entries=()
  if (( ${#DASHBOARD_BODY[@]}   > 0 )); then entries+=("${DASHBOARD_BODY[@]}");   fi
  if (( ${#DASHBOARD_STATUS[@]} > 0 )); then entries+=("${DASHBOARD_STATUS[@]}"); fi
  refresh_start ${entries[@]+"${entries[@]}"}
}

# Block until every component has reported (or the cycle blows its deadline),
# animating the spinner while we wait.
dashboard_await_refresh() {
  local total frames i=0
  total=$(refresh_total)
  frames=${#UI_SPINNER[@]}
  while ! refresh_done; do
    if refresh_expired "$DASHBOARD_REFRESH_TIMEOUT_SECONDS"; then
      refresh_abandon "$DASHBOARD_REFRESH_TIMEOUT_SECONDS"
      break
    fi
    dashboard_paint_status "${UI_SPINNER[i % frames]}" "$(refresh_completed)" "$total"
    i=$(( i + 1 ))
    sleep 0.1
  done
}

# Pull the finished cycle into frame state. Nothing on screen changes until the
# next paint, which is what makes the swap atomic.
dashboard_collect() {
  local entry name out frame='' failed=()
  for entry in ${DASHBOARD_BODY[@]+"${DASHBOARD_BODY[@]}"}; do
    name="${entry%%:*}"
    out=$(refresh_output "$name")
    # $() ate the fragment's trailing newline; put exactly one back so sections
    # keep their single blank-line separation.
    if [[ -n $out ]]; then frame+="${out}"$'\n'; fi
  done
  DASHBOARD_FRAME="${frame%$'\n'}"
  DASHBOARD_VERSION=''
  for entry in ${DASHBOARD_STATUS[@]+"${DASHBOARD_STATUS[@]}"}; do
    out=$(refresh_output "${entry%%:*}")
    if [[ -n $out ]]; then DASHBOARD_VERSION+="$out"; fi
  done
  DASHBOARD_UPDATED_AT=$(date +%H:%M:%S)
  while IFS= read -r name; do failed+=("$name"); done < <(refresh_failed)
  DASHBOARD_FAILED=(${failed[@]+"${failed[@]}"})
  DASHBOARD_TOTAL=$(refresh_total)
  refresh_log_stderr
}

# --- Loop --------------------------------------------------------------------

# Sleep the refresh interval. Backgrounded and waited on rather than run in the
# foreground: bash defers traps until a foreground child exits, so a plain
# `sleep 300` would sit on a SIGTERM for up to five minutes.
dashboard_sleep() {
  sleep "$1" &
  DASHBOARD_SLEEP_PID=$!
  wait "$DASHBOARD_SLEEP_PID" 2>/dev/null || true
  DASHBOARD_SLEEP_PID=''
}

dashboard_shutdown() {
  if [[ $DASHBOARD_SHUTDOWN == true ]]; then return 0; fi
  DASHBOARD_SHUTDOWN=true
  if [[ -n $DASHBOARD_SLEEP_PID ]]; then kill "$DASHBOARD_SLEEP_PID" 2>/dev/null || true; fi
  refresh_cleanup
  # Repaint the settled frame so the shell prompt lands below the dashboard
  # rather than on top of the status bar we were animating.
  if [[ -t 1 ]] && (( DASHBOARD_REFRESH_MINUTES > 0 )); then dashboard_paint; fi
  ui_cursor_show
}

dashboard_loop() {
  dashboard_register_components

  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    ui_cursor_hide
    dashboard_spawn_refresh
    dashboard_await_refresh
    dashboard_collect
    ui_line_erase
    printf '%s\n\n%s\n' "$(dashboard_status_line)" "$DASHBOARD_FRAME"
    return
  fi

  ui_cursor_hide
  DASHBOARD_FRAME="  $(ui_paint "$UI_MUTED" 'Fetching…')"
  dashboard_paint
  while true; do
    dashboard_spawn_refresh
    dashboard_await_refresh
    dashboard_collect
    dashboard_paint
    dashboard_sleep "$(( DASHBOARD_REFRESH_MINUTES * 60 ))"
  done
}

trap 'dashboard_shutdown; exit 130' INT TERM
trap dashboard_shutdown EXIT

requirements_check
dashboard_loop
