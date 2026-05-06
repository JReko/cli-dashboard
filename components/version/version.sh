#!/usr/bin/env bash
# components/version/version.sh — version component orchestrator. Sources its
# features and exposes a single render function the dashboard calls.
#
# Unlike other components this one renders inline (no section header, no
# newline) — its output is appended to the dashboard status bar.

VERSION_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR source=update_check.sh
source "${VERSION_COMPONENT_DIR}/update_check.sh"

version_render() {
  config_enabled FEATURE_VERSION_UPDATE_CHECK || return
  version_update_check_render
}
