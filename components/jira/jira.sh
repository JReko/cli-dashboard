#!/usr/bin/env bash
# components/jira/jira.sh — jira component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.

JIRA_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=assigned_issues.sh
source "${JIRA_COMPONENT_DIR}/assigned_issues.sh"

jira_render() {
  ui_section_header "$UI_ICON_JIRA" "Jira"
  config_enabled FEATURE_JIRA_ASSIGNED_ISSUES && jira_assigned_issues_check
}
