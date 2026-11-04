#!/usr/bin/env bash
# dashboard.sh — entry point. Validates requirements, then renders enabled
# components on a refresh loop.
#
# Refreshes run in the background: every component is fetched+rendered in its
# own subprocess while the previous frame stays on screen with a spinner in the
# status bar. The frame is swapped in one repaint once all of them are in, so
# the dashboard is never half-updated and never blank.
#
# Components publish numbers with ui_metric; the pulse strip on top is drawn
# from them in the foreground once every worker is in.
#
# Each body component is drawn in a rounded panel. Once the terminal is
# DASHBOARD_WIDE_COLUMNS wide, panels stack into side-by-side columns
# (DASHBOARD_COLUMN); narrower terminals stack them all in one. Table rows are
# trimmed ("+N more") so the frame fits the terminal height. A resize triggers
# a refresh at the new size.

set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh
source "${DASHBOARD_DIR}/lib/ui.sh"
# shellcheck source=lib/log.sh
source "${DASHBOARD_DIR}/lib/log.sh"
# shellcheck source=config.sh
source "${DASHBOARD_DIR}/config.sh"
# shellcheck source=lib/refresh.sh
source "${DASHBOARD_DIR}/lib/refresh.sh"
# shellcheck source=lib/demo.sh
source "${DASHBOARD_DIR}/lib/demo.sh"
# shellcheck source=requirements.sh
source "${DASHBOARD_DIR}/requirements.sh"
# shellcheck source=components/brew/brew.sh
source "${DASHBOARD_DIR}/components/brew/brew.sh"
# shellcheck source=components/github/github.sh
source "${DASHBOARD_DIR}/components/github/github.sh"
# shellcheck source=components/pulse/pulse.sh
source "${DASHBOARD_DIR}/components/pulse/pulse.sh"
# shellcheck source=components/jira/jira.sh
source "${DASHBOARD_DIR}/components/jira/jira.sh"
# shellcheck source=components/version/version.sh
source "${DASHBOARD_DIR}/components/version/version.sh"

# --- Frame state -------------------------------------------------------------
# What is currently on screen. Held across cycles so a refresh in flight can
# keep showing the last good frame.
DASHBOARD_FRAME=''            # body: every section, concatenated
DASHBOARD_VERSION=''          # version component's inline status-bar fragment
DASHBOARD_UPDATED_AT=''       # clock of the last completed refresh
DASHBOARD_FAILED=()           # component names that failed last cycle
DASHBOARD_TOTAL=0             # components in the last cycle
DASHBOARD_SHUTDOWN=false
DASHBOARD_SLEEP_PID=''

DASHBOARD_COLS=80             # terminal width the current layout was built for
DASHBOARD_LINES=0             # terminal height; 0 = unknown, nothing is trimmed

# Registry. Order here is priority order on screen: what needs me first. Body
# components render a panel; status components render inline into the status
# bar. DASHBOARD_COLUMN says which column a panel stacks into on wide
# terminals; narrow terminals stack everything in one.
DASHBOARD_BODY=()
DASHBOARD_STATUS=()
DASHBOARD_PULSE=false         # pulse strip on top, rendered in the foreground
declare -A DASHBOARD_COLUMN=()

dashboard_register_components() {
  DASHBOARD_BODY=()
  DASHBOARD_STATUS=()
  DASHBOARD_COLUMN=()
  DASHBOARD_PULSE=false
  if config_enabled COMPONENT_PULSE;   then DASHBOARD_PULSE=true; fi
  if config_enabled COMPONENT_GITHUB;  then DASHBOARD_BODY+=(github:github_render); DASHBOARD_COLUMN[github]=1; fi
  if config_enabled COMPONENT_JIRA;    then DASHBOARD_BODY+=(jira:jira_render);     DASHBOARD_COLUMN[jira]=2;   fi
  if config_enabled COMPONENT_BREW;    then DASHBOARD_BODY+=(brew:brew_render);     DASHBOARD_COLUMN[brew]=2;   fi
  if config_enabled COMPONENT_VERSION; then DASHBOARD_STATUS+=(version:version_render); fi
}

# --- Layout ------------------------------------------------------------------

# dashboard_measure — terminal size. Asked of /dev/tty with stty: tput inside
# $(...) has no tty on stdout and silently answers 80x24. Off a tty (pipes,
# screenshots) COLUMNS/LINES are used if set, else 100 wide and no height cap.
dashboard_measure() {
  local cols='' lines='' size=''
  if [[ -t 1 ]]; then
    size=$(stty size </dev/tty) || size=''
    read -r lines cols <<<"$size" || true
  fi
  if [[ ! $cols =~ ^[0-9]+$ ]] || (( cols < 40 )); then cols=${COLUMNS:-}; fi
  if [[ ! $cols =~ ^[0-9]+$ ]] || (( cols < 40 )); then cols=100; fi
  if [[ ! $lines =~ ^[0-9]+$ ]] || (( lines < 10 )); then lines=${LINES:-}; fi
  if [[ ! $lines =~ ^[0-9]+$ ]] || (( lines < 10 )); then lines=0; fi
  DASHBOARD_COLS=$cols
  DASHBOARD_LINES=$lines
}

# dashboard_layout — fill DASHBOARD_LAYOUT with one entry per screen column
# (space separated component names, stacked top to bottom) and REFRESH_WIDTH
# with each panel's content width. The pulse strip spans the full width above.
DASHBOARD_LAYOUT=()
dashboard_layout() {
  local entry name col wide=false
  local -a order=()
  local -A members=()
  DASHBOARD_LAYOUT=()
  REFRESH_WIDTH=()
  if (( DASHBOARD_COLS >= DASHBOARD_WIDE_COLUMNS )); then wide=true; fi
  for entry in ${DASHBOARD_BODY[@]+"${DASHBOARD_BODY[@]}"}; do
    name="${entry%%:*}"
    col=1
    if [[ $wide == true ]]; then col=${DASHBOARD_COLUMN[$name]:-1}; fi
    if [[ -z ${members[$col]+set} ]]; then order+=("$col"); members[$col]=''; fi
    members[$col]+="${members[$col]:+ }$name"
  done
  for col in ${order[@]+"${order[@]}"}; do DASHBOARD_LAYOUT+=("${members[$col]}"); done

  local i
  local -a col_names=()
  for i in "${!DASHBOARD_LAYOUT[@]}"; do
    dashboard_column_width "${#DASHBOARD_LAYOUT[@]}" "$i"
    read -ra col_names <<<"${DASHBOARD_LAYOUT[i]}"
    for name in "${col_names[@]}"; do REFRESH_WIDTH[$name]=$(( UI_REPLY - 4 )); done
  done
  REFRESH_WIDTH[pulse]=$(( DASHBOARD_COLS - 4 ))
}

# dashboard_column_width <columns> <index> — UI_REPLY: outer width of that
# column. Columns are one space apart. With several, the first (the busiest
# source) gets DASHBOARD_MAIN_PERCENT of the width, the rest share what's left;
# the last one takes the rounding remainder.
dashboard_column_width() {
  local count="$1" index="$2" usable main rest each
  usable=$(( DASHBOARD_COLS - (count - 1) ))
  if (( count == 1 )); then UI_REPLY=$usable; return 0; fi
  main=$(( usable * DASHBOARD_MAIN_PERCENT / 100 ))
  rest=$(( usable - main ))
  each=$(( rest / (count - 1) ))
  if (( index == 0 )); then
    UI_REPLY=$main
  elif (( index == count - 1 )); then
    UI_REPLY=$(( rest - each * (count - 2) ))
  else
    UI_REPLY=$each
  fi
}

# --- Panels ------------------------------------------------------------------
# A component's output parsed for the frame: title/badge lifted out, metrics
# dropped, body kept with UI_ROW_MARK / UI_HEAD_MARK on table lines. A section
# is one table: a run of marked rows plus its header row if it has one. KEEP is
# how many rows of each section survive the fit.
declare -A PANEL_TITLE=() PANEL_BADGE=() PANEL_BODY=() PANEL_FIXED=()
declare -A PANEL_SECTIONS=() PANEL_HEADS=() PANEL_KEEP=()

# dashboard_parse_panel <name> — read the component's spool output.
dashboard_parse_panel() {
  local name="$1" line title="$1" badge='' fixed=0 run=0 head=0 sections='' heads=''
  local -a body=()
  while IFS= read -r line; do
    case $line in
      "$UI_PANEL_MARK"T*) title="${line#"$UI_PANEL_MARK"T}"; continue ;;
      "$UI_PANEL_MARK"B*) badge+="${badge:+ }${line#"$UI_PANEL_MARK"B}"; continue ;;
      "$UI_ROW_MARK"* | "$UI_HEAD_MARK"*) ;;
      "$UI_PANEL_MARK"*) continue ;;
    esac
    body+=("$line")
  done < <(refresh_output "$name")
  # Drop trailing blank lines so panels don't grow empty bottoms.
  while (( ${#body[@]} > 0 )) && [[ -z ${body[-1]} ]]; do unset 'body[-1]'; done

  for line in ${body[@]+"${body[@]}"}; do
    if [[ $line == "$UI_ROW_MARK"* ]]; then
      run=$(( run + 1 ))
      continue
    fi
    if (( run > 0 )); then
      sections+="${sections:+ }$run" heads+="${heads:+ }$head" run=0 head=0
    fi
    # A header with no rows under it is just a line.
    fixed=$(( fixed + head )) head=0
    if [[ $line == "$UI_HEAD_MARK"* ]]; then head=1; else fixed=$(( fixed + 1 )); fi
  done
  if (( run > 0 )); then
    sections+="${sections:+ }$run" heads+="${heads:+ }$head"
  else
    fixed=$(( fixed + head ))
  fi

  PANEL_TITLE[$name]="$title"
  PANEL_BADGE[$name]="$badge"
  PANEL_FIXED[$name]=$fixed
  PANEL_SECTIONS[$name]="$sections"
  PANEL_HEADS[$name]="$heads"
  PANEL_KEEP[$name]="$sections"
  if (( ${#body[@]} > 0 )); then PANEL_BODY[$name]=$(printf '%s\n' "${body[@]}"); else PANEL_BODY[$name]=''; fi
}

# _dashboard_section_lines <keep> <rows> <has_head> — UI_REPLY: lines a table
# takes cut to keep rows. A cut adds a "+N more" line; cut to nothing, the
# table vanishes entirely (its feature header still shows the count).
_dashboard_section_lines() {
  if (( $1 >= $2 )); then
    UI_REPLY=$(( $2 + $3 ))
  elif (( $1 == 0 )); then
    UI_REPLY=0
  else
    UI_REPLY=$(( $1 + 1 + $3 ))
  fi
}

# dashboard_panel_height <name> — UI_REPLY: body lines after the fit.
dashboard_panel_height() {
  local name="$1" total=${PANEL_FIXED[$1]} i
  local -a rows keep heads
  read -ra rows <<<"${PANEL_SECTIONS[$name]}"
  read -ra keep <<<"${PANEL_KEEP[$name]}"
  read -ra heads <<<"${PANEL_HEADS[$name]}"
  for i in "${!rows[@]}"; do
    _dashboard_section_lines "${keep[i]}" "${rows[i]}" "${heads[i]}"
    total=$(( total + UI_REPLY ))
  done
  UI_REPLY=$total
}

# dashboard_column_height <names...> — UI_REPLY: outer height of the stack.
dashboard_column_height() {
  local name total=0
  for name in "$@"; do
    dashboard_panel_height "$name"
    total=$(( total + UI_REPLY + 2 ))
  done
  UI_REPLY=$total
}

# _dashboard_fit_used — sets the caller's `used`: lines the stack takes at the
# current keeps. Reads dashboard_fit_column's locals (bash dynamic scope).
_dashboard_fit_used() {
  local i
  used=$base
  for i in "${!sec_keep[@]}"; do
    _dashboard_section_lines "${sec_keep[i]}" "${sec_rows[i]}" "${sec_head[i]}"
    used=$(( used + UI_REPLY ))
  done
}

# dashboard_fit_column <height> <names...> — trim table rows until the stack
# fits height. Every table is capped at the same row count, the largest cap
# that fits, so long lists shrink first and short ones keep everything. Lines
# left over go back one row at a time, in priority (registry) order.
dashboard_fit_column() {
  local height="$1"; shift
  local name i cap=0 total used grown cost
  local -a sec_name=() sec_rows=() sec_head=() sec_keep=() rows heads keep
  for name in "$@"; do
    read -ra rows <<<"${PANEL_SECTIONS[$name]}"
    read -ra heads <<<"${PANEL_HEADS[$name]}"
    for i in "${!rows[@]}"; do
      sec_name+=("$name") sec_rows+=("${rows[i]}") sec_head+=("${heads[i]}") sec_keep+=("${rows[i]}")
      if (( rows[i] > cap )); then cap=${rows[i]}; fi
    done
  done
  dashboard_column_height "$@"
  total=$UI_REPLY
  if (( total <= height || ${#sec_rows[@]} == 0 )); then return 0; fi

  # Everything but the tables: borders and fixed lines.
  local base=0
  for name in "$@"; do base=$(( base + PANEL_FIXED[$name] + 2 )); done

  while (( cap > 0 )); do
    cap=$(( cap - 1 ))
    for i in "${!sec_rows[@]}"; do
      sec_keep[i]=$(( sec_rows[i] < cap ? sec_rows[i] : cap ))
    done
    _dashboard_fit_used
    if (( used <= height )); then break; fi
  done

  grown=true
  while [[ $grown == true ]]; do
    grown=false
    for i in "${!sec_keep[@]}"; do
      if (( sec_keep[i] >= sec_rows[i] )); then continue; fi
      _dashboard_section_lines "${sec_keep[i]}" "${sec_rows[i]}" "${sec_head[i]}"
      cost=$UI_REPLY
      _dashboard_section_lines $(( sec_keep[i] + 1 )) "${sec_rows[i]}" "${sec_head[i]}"
      cost=$(( UI_REPLY - cost ))
      if (( used + cost <= height )); then
        sec_keep[i]=$(( sec_keep[i] + 1 ))
        used=$(( used + cost ))
        grown=true
      fi
    done
  done

  for name in "$@"; do
    keep=()
    for i in "${!sec_name[@]}"; do
      if [[ ${sec_name[i]} == "$name" ]]; then keep+=("${sec_keep[i]}"); fi
    done
    PANEL_KEEP[$name]="${keep[*]}"
  done
}

# dashboard_panel_lines <name> — the body as it will be boxed: marks stripped,
# each table cut to its KEEP with a "+N more" line in place of the rest.
dashboard_panel_lines() {
  local name="$1" line run=-1 seen=0 hidden=0 indent='' in_run=false head=''
  local -a keep
  if [[ -z ${PANEL_BODY[$name]} ]]; then return 0; fi
  read -ra keep <<<"${PANEL_KEEP[$name]}"
  while IFS= read -r line; do
    if [[ $line == "$UI_ROW_MARK"* ]]; then
      line="${line#"$UI_ROW_MARK"}"
      if [[ $in_run == false ]]; then
        in_run=true run=$(( run + 1 )) seen=0 hidden=0 indent="${line%%[! ]*}"
        if [[ -n $head ]] && (( keep[run] > 0 )); then printf '%s\n' "$head"; fi
        head=''
      fi
      seen=$(( seen + 1 ))
      if (( seen <= keep[run] )); then printf '%s\n' "$line"; else hidden=$(( hidden + 1 )); fi
      continue
    fi
    if [[ $in_run == true ]]; then _dashboard_more "$indent" "$hidden" "${keep[run]}"; in_run=false; fi
    if [[ -n $head ]]; then printf '%s\n' "$head"; head=''; fi
    if [[ $line == "$UI_HEAD_MARK"* ]]; then head="${line#"$UI_HEAD_MARK"}"; continue; fi
    printf '%s\n' "$line"
  done <<<"${PANEL_BODY[$name]}"
  if [[ $in_run == true ]]; then _dashboard_more "$indent" "$hidden" "${keep[run]}"; fi
  if [[ -n $head ]]; then printf '%s\n' "$head"; fi
}

# _dashboard_more <indent> <hidden> <kept> — the "+N more" line of a cut table.
_dashboard_more() {
  if (( $2 == 0 || $3 == 0 )); then return 0; fi
  printf '%s%s+%s more%s\n' "$1" "$UI_MUTED" "$2" "$UI_RESET"
}

# dashboard_box <name> <width> <height> — the panel, boxed, height lines tall.
dashboard_box() {
  local name="$1" width="$2" height="$3"
  local -a body=()
  mapfile -t body < <(dashboard_panel_lines "$name")
  ui_panel "$width" "$height" "${PANEL_TITLE[$name]}" "${PANEL_BADGE[$name]}" \
    ${body[@]+"${body[@]}"}
}

# dashboard_build_frame — the whole body: pulse on top, then the columns side
# by side, every column fitted to the same height. The last panel of a shorter
# column stretches so all columns end on the same line.
dashboard_build_frame() {
  local name i j height=0 budget=0 width outer last tallest=0 out
  local -a col_names=() lines=() column=() col_text=() col_width=()

  if [[ $DASHBOARD_PULSE == true ]]; then
    dashboard_parse_panel pulse
    dashboard_panel_height pulse
    mapfile -t lines < <(dashboard_box pulse "$DASHBOARD_COLS" $(( UI_REPLY + 2 )))
    printf '%s\n' "${lines[@]}"
    budget=-${#lines[@]}
  fi
  if (( ${#DASHBOARD_LAYOUT[@]} == 0 )); then return 0; fi

  for i in "${!DASHBOARD_LAYOUT[@]}"; do
    read -ra col_names <<<"${DASHBOARD_LAYOUT[i]}"
    for name in "${col_names[@]}"; do dashboard_parse_panel "$name"; done
    dashboard_column_height "${col_names[@]}"
    if (( UI_REPLY > height )); then height=$UI_REPLY; fi
  done

  # Leave room for the status bar, the blank line under it and the line the
  # cursor rests on (plus the shell prompt in single-render mode).
  if [[ $DASHBOARD_FIT_HEIGHT == true ]] && (( DASHBOARD_LINES > 0 )); then
    budget=$(( budget + DASHBOARD_LINES - 3 ))
    if (( DASHBOARD_REFRESH_MINUTES == 0 )); then budget=$(( budget - 1 )); fi
    if (( height > budget )); then height=$budget; fi
  fi

  for i in "${!DASHBOARD_LAYOUT[@]}"; do
    read -ra col_names <<<"${DASHBOARD_LAYOUT[i]}"
    dashboard_column_width "${#DASHBOARD_LAYOUT[@]}" "$i"
    width=$UI_REPLY
    dashboard_fit_column "$height" "${col_names[@]}"
    dashboard_column_height "${col_names[@]}"
    local stretch=$(( height - UI_REPLY ))
    if (( stretch < 0 )); then stretch=0; fi
    column=()
    last=$(( ${#col_names[@]} - 1 ))
    for j in "${!col_names[@]}"; do
      dashboard_panel_height "${col_names[j]}"
      outer=$(( UI_REPLY + 2 ))
      if (( j == last )); then outer=$(( outer + stretch )); fi
      mapfile -t lines < <(dashboard_box "${col_names[j]}" "$width" "$outer")
      column+=("${lines[@]}")
    done
    if (( ${#column[@]} > tallest )); then tallest=${#column[@]}; fi
    col_text+=("$(printf '%s\n' "${column[@]}")")
    col_width+=("$width")
  done

  # A column with nothing left to trim can still be taller than the rest; the
  # others are padded with blank space under their last panel.
  local -a grid=()
  for i in "${!col_text[@]}"; do
    mapfile -t column <<<"${col_text[i]}"
    printf -v out '%*s' "${col_width[i]}" ''
    for (( j = 0; j < tallest; j++ )); do
      if (( i > 0 )); then grid[j]+=' '; fi
      grid[j]+="${column[j]:-$out}"
    done
  done
  printf '%s\n' "${grid[@]}"
}

# --- Status bar --------------------------------------------------------------

# dashboard_failure_segment — nothing when the last cycle was clean, otherwise
# names the sources that failed and points at the log.
dashboard_failure_segment() {
  local failed=${#DASHBOARD_FAILED[@]} names='' name
  if (( failed == 0 )); then return 0; fi
  for name in "${DASHBOARD_FAILED[@]}"; do
    if [[ -n $names ]]; then names+=', '; fi
    names+="$name"
  done
  if (( failed >= DASHBOARD_TOTAL )); then
    printf '%s %s' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_KO" "all ${failed} sources failed")"
  else
    printf '%s %s' \
      "$(ui_paint "$UI_WARN" "$UI_ICON_WARN")" \
      "$(ui_paint "$UI_WARN" "${names} failed")"
  fi
}

# dashboard_status_line [<spinner> <done> <total>] — the top line, no trailing
# newline. Passing a spinner frame renders it as "refresh in flight".
dashboard_status_line() {
  local spinner="${1:-}" done_n="${2:-0}" total="${3:-0}"
  local segments=() segment line='' sep

  if [[ -n $spinner ]]; then
    segments+=("$(ui_paint "$UI_INFO" "${spinner} Refreshing ${done_n}/${total} sources")")
  fi
  segments+=("$(ui_paint "$UI_DIM$UI_MUTED" "Updated ${DASHBOARD_UPDATED_AT:-—}")")
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    segments+=("$(ui_paint "$UI_DIM$UI_MUTED" 'single render')")
  else
    segments+=("$(ui_paint "$UI_DIM$UI_MUTED" "refresh every ${DASHBOARD_REFRESH_MINUTES}m")")
  fi
  segment=$(dashboard_failure_segment)
  if [[ -n $segment ]]; then segments+=("$segment"); fi
  if [[ -n $DASHBOARD_VERSION ]]; then segments+=("$DASHBOARD_VERSION"); fi

  sep=" $(ui_paint "$UI_MUTED" '·') "
  for segment in "${segments[@]}"; do
    if [[ -n $line ]]; then line+="$sep"; fi
    line+="$segment"
  done
  printf '%s' "$line"
}

# --- Painting ----------------------------------------------------------------

# The status bar sits on line 1 of the frame while looping; in single-render
# mode it is just the line we are standing on.
dashboard_status_seek() {
  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    printf '\r'
  else
    ui_cursor_home
  fi
}

# dashboard_paint_status <spinner> <done> <total> — rewrite the status bar in
# place. Cheap enough to animate, and it never touches the body below.
dashboard_paint_status() {
  if [[ ! -t 1 ]]; then return 0; fi
  dashboard_status_seek
  ui_line_erase
  printf '%s' "$(dashboard_status_line "$@")"
}

# dashboard_paint — repaint status bar + body from frame state.
dashboard_paint() {
  ui_screen_reset
  ui_line_erase
  printf '%s\n\n%s\n' "$(dashboard_status_line)" "$DASHBOARD_FRAME"
}

# --- Refresh cycle -----------------------------------------------------------

dashboard_spawn_refresh() {
  local entries=()
  dashboard_measure
  dashboard_layout
  if (( ${#DASHBOARD_BODY[@]}   > 0 )); then entries+=("${DASHBOARD_BODY[@]}");   fi
  if (( ${#DASHBOARD_STATUS[@]} > 0 )); then entries+=("${DASHBOARD_STATUS[@]}"); fi
  refresh_start ${entries[@]+"${entries[@]}"}
}

# Block until every component has reported (or the cycle blows its deadline),
# animating the spinner while we wait.
dashboard_await_refresh() {
  local total frames i=0
  total=$(refresh_total)
  frames=${#UI_SPINNER[@]}
  while ! refresh_done; do
    if refresh_expired "$DASHBOARD_REFRESH_TIMEOUT_SECONDS"; then
      refresh_abandon "$DASHBOARD_REFRESH_TIMEOUT_SECONDS"
      break
    fi
    dashboard_paint_status "${UI_SPINNER[i % frames]}" "$(refresh_completed)" "$total"
    i=$(( i + 1 ))
    sleep 0.1
  done
}

# Pull the finished cycle into frame state. Nothing on screen changes until the
# next paint, which is what makes the swap atomic.
dashboard_collect() {
  local entry name out failed=()
  if [[ $DASHBOARD_PULSE == true ]]; then dashboard_render_pulse; fi
  DASHBOARD_FRAME="$(dashboard_build_frame)"
  DASHBOARD_VERSION=''
  for entry in ${DASHBOARD_STATUS[@]+"${DASHBOARD_STATUS[@]}"}; do
    out=$(refresh_output "${entry%%:*}")
    if [[ -n $out ]]; then DASHBOARD_VERSION+="$out"; fi
  done
  DASHBOARD_UPDATED_AT=$(date +%H:%M:%S)
  while IFS= read -r name; do failed+=("$name"); done < <(refresh_failed)
  DASHBOARD_FAILED=(${failed[@]+"${failed[@]}"})
  DASHBOARD_TOTAL=$(refresh_total)
  refresh_log_stderr
}

# dashboard_render_pulse — gather every body component's ui_metric lines into
# PULSE_METRICS, then render the pulse strip into the cycle's spool so it is
# laid out like any other panel.
dashboard_render_pulse() {
  local entry line key
  PULSE_METRICS=()
  for entry in ${DASHBOARD_BODY[@]+"${DASHBOARD_BODY[@]}"}; do
    while IFS= read -r line; do
      if [[ $line != "$UI_PANEL_MARK"M*=* ]]; then continue; fi
      line="${line#"$UI_PANEL_MARK"M}"
      key="${line%%=*}"
      # shellcheck disable=SC2034 # read by components/pulse
      PULSE_METRICS[$key]="${line#*=}"
    done < <(refresh_output "${entry%%:*}")
  done
  if ! UI_WIDTH="${REFRESH_WIDTH[pulse]}" pulse_render >"$(refresh_cycle_dir)/pulse.out"; then
    log_error "pulse" "render failed"
  fi
}

# --- Loop --------------------------------------------------------------------

# Sleep the refresh interval. Backgrounded and waited on rather than run in the
# foreground: bash defers traps until a foreground child exits, so a plain
# `sleep 300` would sit on a SIGTERM for up to five minutes.
dashboard_sleep() {
  sleep "$1" &
  DASHBOARD_SLEEP_PID=$!
  wait "$DASHBOARD_SLEEP_PID" 2>/dev/null || true
  DASHBOARD_SLEEP_PID=''
}

# On resize, cut the sleep short so the next cycle re-lays out at the new
# width. Mid-refresh resizes are picked up by the cycle after.
dashboard_on_winch() {
  if [[ -n $DASHBOARD_SLEEP_PID ]]; then kill "$DASHBOARD_SLEEP_PID" 2>/dev/null || true; fi
}

dashboard_shutdown() {
  if [[ $DASHBOARD_SHUTDOWN == true ]]; then return 0; fi
  DASHBOARD_SHUTDOWN=true
  if [[ -n $DASHBOARD_SLEEP_PID ]]; then kill "$DASHBOARD_SLEEP_PID" 2>/dev/null || true; fi
  refresh_cleanup
  # Repaint the settled frame so the shell prompt lands below the dashboard
  # rather than on top of the status bar we were animating.
  if [[ -t 1 ]] && (( DASHBOARD_REFRESH_MINUTES > 0 )); then dashboard_paint; fi
  ui_cursor_show
}

dashboard_loop() {
  dashboard_register_components

  if (( DASHBOARD_REFRESH_MINUTES == 0 )); then
    ui_cursor_hide
    dashboard_spawn_refresh
    dashboard_await_refresh
    dashboard_collect
    ui_line_erase
    printf '%s\n\n%s\n' "$(dashboard_status_line)" "$DASHBOARD_FRAME"
    return
  fi

  ui_cursor_hide
  DASHBOARD_FRAME="  $(ui_paint "$UI_MUTED" 'Fetching…')"
  dashboard_paint
  while true; do
    dashboard_spawn_refresh
    dashboard_await_refresh
    dashboard_collect
    dashboard_paint
    dashboard_sleep "$(( DASHBOARD_REFRESH_MINUTES * 60 ))"
  done
}

trap 'dashboard_shutdown; exit 130' INT TERM
trap dashboard_shutdown EXIT
trap dashboard_on_winch WINCH

requirements_check
dashboard_loop
