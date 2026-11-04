#!/usr/bin/env bash
# components/brew/outdated_packages.sh — installed formulae with newer versions
# available. Rendering lives in brew_render_outdated (brew.sh).

brew_outdated_packages_check() {
  local payload err_file err
  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_brew_outdated_formulae_payload)
  else
    err_file=$(mktemp)
    if ! payload=$(brew outdated --formula --json=v2 2>"$err_file"); then
      err=$(<"$err_file"); rm -f "$err_file"
      log_error "brew/outdated_packages" "$err"
      ui_feature_error "Outdated packages"
      return 1  # error line already rendered; the orchestrator collects the failure
    fi
    rm -f "$err_file"
  fi

  # brew prepends a progress banner (e.g. "==> Downloading Homebrew API data")
  # to stdout on exit 0 when its API cache is stale; keep only the JSON that
  # follows so it doesn't poison jq.
  payload=$(awk 'seen || /^[[{]/ { seen=1; print }' <<<"$payload")

  if ! require_json "brew/outdated_packages" "$payload"; then
    ui_feature_error "Outdated packages"
    return 1  # error line already rendered; the orchestrator collects the failure
  fi

  brew_render_outdated formulae "$UI_ICON_PACKAGE" "Outdated packages" \
    "$(jq -r '.formulae[] | [.name, (.installed_versions | join(", ")), .current_version] | @tsv' <<<"$payload")"
}
