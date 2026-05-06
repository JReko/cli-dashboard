#!/usr/bin/env bash
# components/github/github.sh — github component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.

GITHUB_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=api_status.sh
source "${GITHUB_COMPONENT_DIR}/api_status.sh"
# shellcheck source-path=SCRIPTDIR source=prs_review_requested.sh
source "${GITHUB_COMPONENT_DIR}/prs_review_requested.sh"

github_render() {
  ui_section_header "$UI_ICON_GITHUB" "GitHub"
  config_enabled FEATURE_GITHUB_API_STATUS && github_api_status_check
  if config_enabled FEATURE_GITHUB_PRS_REVIEW_REQUESTED; then
    printf '\n'
    github_prs_review_requested_check
  fi
}
