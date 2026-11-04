#!/usr/bin/env bash
# components/brew/brew.sh — homebrew component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.
#
# Renders an installed → latest table, major-version bumps tagged in yellow.
# BREW_COMPACT=true squeezes each feature into one line of names instead.
# Publishes brew_<kind>_outdated / brew_<kind>_major to the pulse strip.
#
# Returns non-zero if any enabled feature failed, so the dashboard status bar
# can flag the source. Features still render their own error line.

BREW_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=outdated_packages.sh
source "${BREW_COMPONENT_DIR}/outdated_packages.sh"
# shellcheck source-path=SCRIPTDIR source=outdated_casks.sh
source "${BREW_COMPONENT_DIR}/outdated_casks.sh"

# brew_render_outdated <kind> <icon> <title> <tsv> — shared renderer for
# outdated formulae/casks. kind names the pulse metrics. tsv rows: name,
# installed, latest.
brew_render_outdated() {
  local kind="$1" icon="$2" title="$3" tsv="$4" count=0 name installed latest color
  local cells=() rows=() major=0
  if [[ -n $tsv ]]; then mapfile -t rows <<<"$tsv"; fi
  count=${#rows[@]}
  for name in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r name installed latest <<<"$name"
    if _brew_is_major "$installed" "$latest"; then major=$(( major + 1 )); fi
  done
  ui_metric "brew_${kind}_outdated" "$count"
  ui_metric "brew_${kind}_major" "$major"

  if (( count == 0 )) || ! config_enabled BREW_COMPACT; then
    ui_feature_header "$icon" "$title" "$count"
    if (( count == 0 )); then return 0; fi
    printf '%s\n' "${rows[@]}" | while IFS=$'\t' read -r name installed latest; do
      local tag=''
      _brew_bump_color "$installed" "$latest"
      color="$UI_REPLY"
      if [[ $color == "$UI_OK" ]]; then color="$UI_TEXT"; else tag='major'; fi
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(ui_cell "$UI_TEXT" "$name")" \
        "$(ui_cell "$UI_MUTED" "$installed")" \
        "$(ui_cell "$UI_MUTED" "$UI_ICON_ARROW")" \
        "$(ui_cell "$color" "$latest")" \
        "$(ui_cell "$UI_WARN" "$tag")"
    done | ui_table 2 "$UI_WIDTH" '' '' '' '' ''
    return 0
  fi

  # Compact: "<icon> Title  N  a · b · c · +2" on a single line.
  local header
  header=$(ui_feature_header "$icon" "$title" "$count")
  ui_strip "$header"
  local room=$(( UI_WIDTH - ${#UI_REPLY} - 2 ))
  for name in "${rows[@]}"; do
    IFS=$'\t' read -r name installed latest <<<"$name"
    _brew_bump_color "$installed" "$latest"
    color="$UI_REPLY"
    if [[ $color == "$UI_OK" ]]; then color="$UI_SUBTLE"; fi
    cells+=("$(ui_cell "$color" "$name")")
  done
  ui_inline_list "$room" "${cells[@]}"
  printf '%s  %s\n' "$header" "$UI_REPLY"
}

# _brew_is_major <installed> <latest> — true when the first segment changed.
_brew_is_major() {
  [[ ${1%%.*} != "${2%%.*}" ]]
}

# _brew_bump_color <installed> <latest> — UI_REPLY: warn on a major bump.
_brew_bump_color() {
  if _brew_is_major "$1" "$2"; then UI_REPLY="$UI_WARN"; else UI_REPLY="$UI_OK"; fi
}

brew_render() {
  local rc=0
  ui_panel_title "$UI_ICON_BREW" "Homebrew"
  if config_enabled FEATURE_BREW_OUTDATED_PACKAGES; then
    brew_outdated_packages_check || rc=1
  fi
  if config_enabled FEATURE_BREW_OUTDATED_CASKS; then
    if ! config_enabled BREW_COMPACT; then printf '\n'; fi
    brew_outdated_casks_check || rc=1
  fi
  return "$rc"
}
