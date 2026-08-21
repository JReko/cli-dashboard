#!/usr/bin/env bash
# components/version/update_check.sh — compares the running version (latest
# reachable git tag) against the most recent GitHub release.

VERSION_UPDATE_CHECK_REPO="JReko/cli-dashboard"

# Echoes the running version: nearest tag, or "<tag>-<n>-g<sha>[-dirty]" when
# ahead of it, or just a short SHA when no tags are reachable.
version_update_check_current() {
  if config_enabled DASHBOARD_DEMO; then
    printf 'v1.0.0'
    return
  fi
  git -C "$DASHBOARD_DIR" describe --tags --always --dirty 2>/dev/null
}

# Echoes the latest release tag from GitHub.
version_update_check_latest() {
  if config_enabled DASHBOARD_DEMO; then
    demo_version_update_check_payload | jq -r '.tag_name'
    return
  fi
  gh api "repos/${VERSION_UPDATE_CHECK_REPO}/releases/latest" --jq '.tag_name' 2>/dev/null
}

# Prints the inline header indicator.
#   on latest:   dim "<version>"
#   outdated:    warn "<icon> <current> → <latest>"
# Prints nothing and returns non-zero when either version can't be resolved, so
# the dashboard reports it as a failed source instead of silently dropping it.
version_update_check_render() {
  local current latest
  current=$(version_update_check_current)
  latest=$(version_update_check_latest)
  if [[ -z $current || -z $latest ]]; then
    log_error "version/update_check" \
      "could not resolve versions (current='${current}' latest='${latest}')"
    return 1
  fi

  if [[ $current == "$latest" ]]; then
    printf '%s%s%s' "$UI_DIM$UI_MUTED" "$current" "$UI_RESET"
  else
    printf '%s %s %s %s' \
      "$(ui_paint "$UI_WARN" "$UI_ICON_WARN")" \
      "$(ui_paint "$UI_SUBTLE" "$current")" \
      "$(ui_paint "$UI_MUTED" "$UI_ICON_ARROW")" \
      "$(ui_paint "$UI_WARN" "$latest")"
  fi
}
