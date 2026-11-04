#!/usr/bin/env bash
# components/github/api_status.sh — checks if the GitHub API responds for our
# token. Shows as the panel badge ("✔ @login"); only a failure takes a row.

github_api_status_check() {
  local login
  if config_enabled DASHBOARD_DEMO; then
    login=$(demo_github_api_login)
  elif ! login=$(gh api /user --jq '.login' 2>&1); then
    log_error "github/api_status" "$login"
    ui_panel_badge "$(ui_paint "$UI_KO" "$UI_ICON_KO API")"
    ui_feature_error "API access"
    return 1
  fi
  ui_panel_badge "$(ui_paint "$UI_OK" "$UI_ICON_OK") $(ui_paint "$UI_SUBTLE" "@$login")"
}
