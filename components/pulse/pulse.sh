#!/usr/bin/env bash
# components/pulse/pulse.sh — pulse component orchestrator. A full-width strip
# above the other panels: meters summarising what the other components found,
# plus the review queue's 14-day trend beside them.
#
# Unlike other components it fetches nothing. It reads the numbers the others
# publish with ui_metric, which the dashboard gathers into PULSE_METRICS, so
# it renders in the foreground once every worker is in.

PULSE_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Filled by the dashboard each cycle: metric key → value.
declare -A PULSE_METRICS=()

# shellcheck source-path=SCRIPTDIR source=meters.sh
source "${PULSE_COMPONENT_DIR}/meters.sh"
# shellcheck source-path=SCRIPTDIR source=trend.sh
source "${PULSE_COMPONENT_DIR}/trend.sh"

# Trend block width: 14 one-column bars with a gap between each.
PULSE_TREND_WIDTH=$(( PULSE_TREND_DAYS * 2 - 1 ))

pulse_render() {
  local -a meters=() trend=()
  local meter_width=$UI_WIDTH show_trend=false side=false i line pad

  ui_panel_title "$UI_ICON_PULSE" "Pulse"
  if config_enabled FEATURE_PULSE_TREND; then
    pulse_trend_record
    mapfile -t trend < <(pulse_trend_render)
    if (( ${#trend[@]} > 0 )); then show_trend=true; fi
  fi
  # The strip stays short: the trend sits beside the meters when all four
  # still fit in one row next to it, and is left out otherwise.
  if [[ $show_trend == true ]] && config_enabled FEATURE_PULSE_METERS; then
    if (( UI_WIDTH - PULSE_TREND_WIDTH - 3 >= 4 * PULSE_METER_MIN + 9 )); then
      side=true
      meter_width=$(( UI_WIDTH - PULSE_TREND_WIDTH - 3 ))
    else
      show_trend=false trend=()
    fi
  fi
  if config_enabled FEATURE_PULSE_METERS; then
    mapfile -t meters < <(pulse_meters_render "$meter_width")
  fi

  if [[ $side == true ]]; then
    while (( ${#meters[@]} < ${#trend[@]} )); do meters+=(''); done
    for i in "${!meters[@]}"; do
      line="${meters[i]}"
      _ui_visible_len "$line"
      printf -v pad '%*s' $(( meter_width - UI_REPLY )) ''
      printf '%s%s %s│%s %s\n' "$line" "$pad" "$UI_MUTED" "$UI_RESET" "${trend[i]:-}"
    done
    return 0
  fi
  if (( ${#meters[@]} > 0 )); then printf '%s\n' "${meters[@]}"; fi
  if [[ $show_trend == true ]]; then
    if (( ${#meters[@]} > 0 )); then printf '\n'; fi
    printf '%s\n' "${trend[@]}"
  fi
}
