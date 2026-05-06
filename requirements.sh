#!/usr/bin/env bash
# requirements.sh — validate runtime deps and env at startup.

requirements_check() {
  # cmd:formula — gdate ships in coreutils; jira lives in a tap.
  # Demo mode skips real CLIs/tokens; only gdate + jq are needed for mock payloads.
  local required
  if config_enabled DASHBOARD_DEMO; then
    required=(
      gdate:coreutils
      jq:jq
    )
  else
    required=(
      brew:brew
      gdate:coreutils
      gh:gh
      jira:ankitpokhrel/jira-cli/jira-cli
      jq:jq
    )
  fi
  local missing_formulae=() entry cmd formula

  for entry in "${required[@]}"; do
    cmd="${entry%%:*}"
    formula="${entry#*:}"
    command -v "$cmd" >/dev/null 2>&1 || missing_formulae+=("$formula")
  done

  if (( ${#missing_formulae[@]} > 0 )); then
    printf '%s Missing dependencies\n' "$(ui_paint "$UI_KO" "$UI_ICON_KO")" >&2
    printf '%s Install with: %s\n' "$(ui_paint "$UI_MUTED" "·")" "$(ui_paint "$UI_INFO" "brew install ${missing_formulae[*]}")" >&2
    return 1
  fi

  config_enabled DASHBOARD_DEMO && return 0

  if [[ -z "${GH_TOKEN:-}" ]]; then
    printf '%s GH_TOKEN env var not set\n' "$(ui_paint "$UI_KO" "$UI_ICON_KO")" >&2
    return 1
  fi

  if [[ -z "${JIRA_API_TOKEN:-}" ]]; then
    printf '%s JIRA_API_TOKEN env var not set\n' "$(ui_paint "$UI_KO" "$UI_ICON_KO")" >&2
    return 1
  fi

  if [[ -z "${JIRA_HOST:-}" ]]; then
    printf '%s JIRA_HOST env var not set\n' "$(ui_paint "$UI_KO" "$UI_ICON_KO")" >&2
    return 1
  fi
}
