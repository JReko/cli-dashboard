#!/usr/bin/env bash
# components/brew/outdated_packages.sh — installed formulae with newer versions
# available. Per row: name, installed -> latest. Columns padded to widest value.

brew_outdated_packages_check() {
  local payload count
  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_brew_outdated_formulae_payload)
  elif ! payload=$(brew outdated --formula --json=v2 2>&1); then
    printf '  %s Outdated packages %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "ERROR: $payload")"
    return 1
  fi

  count=$(jq '.formulae | length' <<<"$payload")
  printf '  %s Outdated packages %s %s\n' \
    "$(ui_paint "$UI_ACCENT" "$UI_ICON_PACKAGE")" \
    "$(ui_paint "$UI_MUTED" '·')" \
    "$(ui_paint "$UI_TEXT" "$count")"

  if (( count == 0 )); then
    printf '    %s\n' "$(ui_paint "$UI_MUTED" '(none)')"
    return 0
  fi

  local rows=() name installed latest name_w=0 installed_w=0
  while IFS=$'\t' read -r name installed latest; do
    rows+=("$name"$'\t'"$installed"$'\t'"$latest")
    (( ${#name}      > name_w      )) && name_w=${#name}
    (( ${#installed} > installed_w )) && installed_w=${#installed}
  done < <(jq -r '.formulae[] | [
      .name,
      (.installed_versions | join(", ")),
      .current_version
    ] | @tsv' <<<"$payload")

  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name installed latest <<<"$row"
    printf '    %s%-*s%s  %s%-*s%s  %s  %s%s%s\n' \
      "$UI_TEXT"   "$name_w"      "$name"      "$UI_RESET" \
      "$UI_MUTED"  "$installed_w" "$installed" "$UI_RESET" \
      "$(ui_paint "$UI_MUTED" "$UI_ICON_ARROW")" \
      "$UI_OK"                    "$latest"    "$UI_RESET"
  done
}
