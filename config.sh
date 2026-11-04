#!/usr/bin/env bash
# config.sh — dashboard configuration. All toggles live here.

# Vars are read by sourcing scripts and via indirect expansion in config_enabled,
# neither of which the linter can see.
# shellcheck disable=SC2034
# Convention:
#   DASHBOARD_REFRESH_MINUTES   — how often the dashboard re-renders. 0 = run once.
#   DASHBOARD_REFRESH_TIMEOUT_SECONDS — per-cycle deadline for a component.
#   COMPONENT_<NAME>            — true|false to enable/disable a whole component.
#   FEATURE_<COMPONENT>_<NAME>  — true|false to enable/disable a single feature.

# --- Refresh -----------------------------------------------------------------
DASHBOARD_REFRESH_MINUTES=5

# Components are refreshed in parallel in the background. A component that
# hasn't reported within this budget is killed and flagged as failed, so one
# wedged CLI can't freeze the whole dashboard. 0 disables the deadline.
DASHBOARD_REFRESH_TIMEOUT_SECONDS=60

# --- Layout ------------------------------------------------------------------
# Terminal width (columns) from which panels sit in side-by-side columns
# (GitHub left; Jira and Homebrew stacked right). Narrower terminals stack every
# panel full width.
DASHBOARD_WIDE_COLUMNS=140

# Share of the width the first (GitHub) column gets in the wide layout.
DASHBOARD_MAIN_PERCENT=55

# Trim table rows ("+N more") so the whole dashboard fits the terminal height.
DASHBOARD_FIT_HEIGHT=true

# Homebrew as one line of names per feature instead of the installed → latest
# table.
BREW_COMPACT=false

# --- Demo --------------------------------------------------------------------
# When true, every component renders fake data instead of hitting real APIs.
# Used to capture the README screenshot without leaking real handles, repos,
# or ticket info. No tokens needed.
DASHBOARD_DEMO=false

# --- Components --------------------------------------------------------------
COMPONENT_BREW=true
COMPONENT_GITHUB=true
COMPONENT_JIRA=true
COMPONENT_PULSE=true
COMPONENT_VERSION=true

# --- Features ----------------------------------------------------------------
FEATURE_BREW_OUTDATED_PACKAGES=true
FEATURE_BREW_OUTDATED_CASKS=true
FEATURE_GITHUB_API_STATUS=true
FEATURE_GITHUB_PRS_AUTHORED=true
FEATURE_GITHUB_PRS_REVIEW_REQUESTED=true
FEATURE_JIRA_ASSIGNED_ISSUES=true
FEATURE_PULSE_METERS=true
FEATURE_PULSE_TREND=true
FEATURE_VERSION_UPDATE_CHECK=true

# --- Helper ------------------------------------------------------------------
# config_enabled <VAR_NAME> — returns 0 if the named var is "true", else 1.
config_enabled() {
  local var="$1"
  [[ "${!var:-false}" == "true" ]]
}

# --- Local overrides ---------------------------------------------------------
# config.local.sh is gitignored. Put personal tweaks there so `git pull` never
# conflicts on this file.
_config_dir="${BASH_SOURCE[0]%/*}"
# shellcheck source=/dev/null
[[ -f "$_config_dir/config.local.sh" ]] && source "$_config_dir/config.local.sh"
unset _config_dir
