#!/usr/bin/env bash
# components/jira/jira.sh — jira component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.
#
# Returns non-zero if any enabled feature failed, so the dashboard status bar
# can flag the source. Features still render their own error line.

JIRA_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=assigned_issues.sh
source "${JIRA_COMPONENT_DIR}/assigned_issues.sh"

jira_render() {
  local rc=0
  ui_section_header "$UI_ICON_JIRA" "Jira"
  if config_enabled FEATURE_JIRA_ASSIGNED_ISSUES; then
    jira_assigned_issues_check || rc=1
  fi
  return "$rc"
}
