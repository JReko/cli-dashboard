#!/usr/bin/env bash
# components/github/api_status.sh — checks if the GitHub API responds for our token.

github_api_status_check() {
  local login
  if config_enabled DASHBOARD_DEMO; then
    login=$(demo_github_api_login)
  elif ! login=$(gh api /user --jq '.login' 2>&1); then
    printf '  %s API access  %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "$login")"
    return 1
  fi
  printf '  %s API access  %s @%s\n' \
    "$(ui_paint "$UI_OK" "$UI_ICON_OK")" \
    "$(ui_paint "$UI_MUTED" '·')" \
    "$(ui_paint "$UI_SUBTLE" "$login")"
}
