#!/usr/bin/env bash
# components/pulse/trend.sh — the review queue over the last 14 days as a
# two-row sparkline, today highlighted.
#
# History lives in PULSE_HISTORY_FILE, one "YYYY-MM-DD count" line per day;
# each refresh overwrites today's line. Days the dashboard didn't run show as
# empty. Demo mode reads a fixed series and writes nothing.

PULSE_TREND_DAYS=14
# Fewer recorded days than this in the window and the sparkline is noise, so
# it isn't drawn at all.
PULSE_TREND_MIN_DAYS=3
PULSE_HISTORY_FILE="${PULSE_HISTORY_FILE:-$HOME/Library/Caches/cli-dashboard/review_history}"

# pulse_trend_record — upsert today's review count. No-op in demo mode or when
# GitHub didn't publish a count this cycle.
pulse_trend_record() {
  local today kept
  if config_enabled DASHBOARD_DEMO; then return 0; fi
  if [[ -z ${PULSE_METRICS[review_count]+set} ]]; then return 0; fi
  today=$(date +%F)
  mkdir -p "$(dirname "$PULSE_HISTORY_FILE")"
  kept=''
  if [[ -f $PULSE_HISTORY_FILE ]]; then
    kept=$(grep -v "^${today} " "$PULSE_HISTORY_FILE" | tail -n $(( PULSE_TREND_DAYS * 4 )) || true)
  fi
  {
    if [[ -n $kept ]]; then printf '%s\n' "$kept"; fi
    printf '%s %s\n' "$today" "${PULSE_METRICS[review_count]}"
  } >"${PULSE_HISTORY_FILE}.part"
  mv -f "${PULSE_HISTORY_FILE}.part" "$PULSE_HISTORY_FILE"
}

# _pulse_trend_history — the "date count" lines to chart.
_pulse_trend_history() {
  if config_enabled DASHBOARD_DEMO; then
    demo_pulse_trend_payload
  elif [[ -f $PULSE_HISTORY_FILE ]]; then
    cat "$PULSE_HISTORY_FILE"
  fi
}

# pulse_trend_render — three lines, PULSE_TREND_WIDTH wide: caption, then the
# two sparkline rows. Prints nothing until PULSE_TREND_MIN_DAYS are recorded.
pulse_trend_render() {
  local -A by_day=()
  local -a values=()
  local day count i today_n caption gap recorded=0
  while read -r day count; do
    if [[ -n $day ]]; then by_day[$day]=$count; fi
  done < <(_pulse_trend_history)
  for (( i = PULSE_TREND_DAYS - 1; i >= 0; i-- )); do
    day=$(gdate -d "-${i} days" +%F)
    if [[ -n ${by_day[$day]+set} ]]; then recorded=$(( recorded + 1 )); fi
    values+=("${by_day[$day]:-0}")
  done
  if (( recorded < PULSE_TREND_MIN_DAYS )); then return 0; fi
  today_n=${values[-1]}
  caption='Review queue 14d'
  gap=$(( PULSE_TREND_WIDTH - ${#caption} - ${#today_n} - 6 ))
  if (( gap < 1 )); then gap=1; fi
  printf '%s%s%s%*s%stoday %s%s%s%s\n' \
    "$UI_SUBTLE" "$caption" "$UI_RESET" "$gap" '' \
    "$UI_MUTED" "$UI_RESET" "$UI_BOLD$UI_ACCENT" "$today_n" "$UI_RESET"
  ui_sparkline 2 "${values[@]}"
}
