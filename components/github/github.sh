#!/usr/bin/env bash
# components/github/github.sh — github component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.
#
# Features render in priority order: what's waiting on me first, then my own
# PRs. API status rides in the panel badge rather than taking a row.
#
# Returns non-zero if any enabled feature failed, so the dashboard status bar
# can flag the source. Features still render their own error line.

GITHUB_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=api_status.sh
source "${GITHUB_COMPONENT_DIR}/api_status.sh"
# shellcheck source-path=SCRIPTDIR source=prs_authored.sh
source "${GITHUB_COMPONENT_DIR}/prs_authored.sh"
# shellcheck source-path=SCRIPTDIR source=prs_review_requested.sh
source "${GITHUB_COMPONENT_DIR}/prs_review_requested.sh"

# jq: `repo($owner)` is the repo label for a search node. The most common
# owner in the list is noise, so its repos show by name only; any other owner
# stays visible (`octocat/spoon-knife`). Bind $owner with `common_owner(nodes)`.
GITHUB_REPO_JQ_DEFS='
  def common_owner(n): n | map(.repository.nameWithOwner | split("/")[0])
    | group_by(.) | max_by(length) | .[0] // "";
  def repo($owner): .repository.nameWithOwner
    | if startswith($owner + "/") then .[($owner | length) + 1:] else . end;
'

# --- State column -------------------------------------------------------------
# One "State" column in words instead of an icon per check. Callers collect
# painted parts most-important first; only the first is spelled out, the rest
# are counted ("CI failing +1") so the column stays narrow.

# github_state_ci_failing / github_state_ci_running <rollup_state> — UI_REPLY:
# the painted CI part; non-zero when it doesn't apply. Split so callers can
# rank them apart: failing checks outrank a conflict, running ones don't.
github_state_ci_failing() {
  if [[ $1 != FAILURE && $1 != ERROR ]]; then return 1; fi
  UI_REPLY="${UI_KO}CI failing$UI_RESET"
}

github_state_ci_running() {
  if [[ $1 != PENDING && $1 != EXPECTED ]]; then return 1; fi
  UI_REPLY="${UI_INFO}CI running$UI_RESET"
}

# github_state_text <part>... — UI_REPLY: the first part, "+N" for the rest.
# Empty when there are none (healthy is quiet).
github_state_text() {
  UI_REPLY=''
  if (( $# == 0 )); then return 0; fi
  UI_REPLY="$1"
  if (( $# > 1 )); then UI_REPLY+=" $UI_MUTED+$(( $# - 1 ))$UI_RESET"; fi
}

github_render() {
  local rc=0 sep=''
  ui_panel_title "$UI_ICON_GITHUB" "GitHub"
  if config_enabled FEATURE_GITHUB_API_STATUS; then
    github_api_status_check || rc=1
  fi
  if config_enabled FEATURE_GITHUB_PRS_REVIEW_REQUESTED; then
    github_prs_review_requested_check || rc=1
    sep=$'\n'
  fi
  if config_enabled FEATURE_GITHUB_PRS_AUTHORED; then
    printf '%s' "$sep"
    github_prs_authored_check || rc=1
  fi
  return "$rc"
}
