#!/usr/bin/env bash
# components/brew/brew.sh — homebrew component orchestrator. Sources its features
# and exposes a single render function the dashboard calls.
#
# Returns non-zero if any enabled feature failed, so the dashboard status bar
# can flag the source. Features still render their own error line.

BREW_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=outdated_packages.sh
source "${BREW_COMPONENT_DIR}/outdated_packages.sh"
# shellcheck source-path=SCRIPTDIR source=outdated_casks.sh
source "${BREW_COMPONENT_DIR}/outdated_casks.sh"

brew_render() {
  local rc=0
  ui_section_header "$UI_ICON_BREW" "Homebrew"
  if config_enabled FEATURE_BREW_OUTDATED_PACKAGES; then
    brew_outdated_packages_check || rc=1
  fi
  if config_enabled FEATURE_BREW_OUTDATED_CASKS; then
    printf '\n'
    brew_outdated_casks_check || rc=1
  fi
  return "$rc"
}
