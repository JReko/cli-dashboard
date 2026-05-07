#!/usr/bin/env bash
# dashboard.sh — entry point. Validates requirements then renders enabled
# components on a configurable refresh loop.

set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh
source "${DASHBOARD_DIR}/lib/ui.sh"
# shellcheck source=lib/log.sh
source "${DASHBOARD_DIR}/lib/log.sh"
# shellcheck source=config.sh
source "${DASHBOARD_DIR}/config.sh"
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

dashboard_status_bar() {
  local refresh status version_indicator
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    refresh='single render'
  else
    refresh="refresh every ${DASHBOARD_REFRESH_MINUTES}m"
  fi
  status=$(printf '%sUpdated %s · %s%s' \
    "$UI_DIM$UI_MUTED" "$(date +%H:%M:%S)" "$refresh" "$UI_RESET")
  if config_enabled COMPONENT_VERSION; then
    version_indicator=$(version_render)
    [[ -n $version_indicator ]] && \
      status+=" $(ui_paint "$UI_MUTED" '·') $version_indicator"
  fi
  printf '%s\n\n' "$status"
}

dashboard_render() {
  dashboard_status_bar
  config_enabled COMPONENT_BREW && brew_render
  config_enabled COMPONENT_GITHUB && github_render
  config_enabled COMPONENT_JIRA && jira_render
}

dashboard_loop() {
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    dashboard_render
    return
  fi
  trap 'tput cnorm 2>/dev/null; printf "\n"; exit 0' INT TERM
  tput civis 2>/dev/null || true
  while true; do
    clear
    dashboard_render
    sleep "$(( DASHBOARD_REFRESH_MINUTES * 60 ))"
  done
}

requirements_check
dashboard_loop
