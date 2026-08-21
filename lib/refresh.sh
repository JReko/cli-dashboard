#!/usr/bin/env bash
# lib/refresh.sh — background refresh engine.
#
# Each enabled component is rendered in its own subprocess into a spool file.
# The foreground keeps the previous frame on screen while they run and swaps in
# the new one only once every component has reported, so a refresh never blanks
# the dashboard nor blocks on the slowest API.
#
# Spool layout, one directory per cycle:
#   <root>/<cycle>/<name>.out     stdout of <name>_render — the frame fragment
#   <root>/<cycle>/<name>.err     anything the component leaked to stderr
#   <root>/<cycle>/<name>.status  exit code, moved into place last so its mere
#                                 presence means "this component is done"

REFRESH_SPOOL_ROOT="${TMPDIR:-/tmp}/cli-dashboard.$$"
REFRESH_CYCLE=0
REFRESH_STARTED_AT=0
REFRESH_NAMES=()
REFRESH_PIDS=()

refresh_cycle_dir() {
  printf '%s/%s' "$REFRESH_SPOOL_ROOT" "$REFRESH_CYCLE"
}

# refresh_start <name>:<render_fn> ... — fork one worker per component.
# Returns immediately; poll with refresh_done / refresh_completed.
refresh_start() {
  local entry name fn dir
  REFRESH_CYCLE=$(( REFRESH_CYCLE + 1 ))
  REFRESH_STARTED_AT=$(date +%s)
  REFRESH_NAMES=()
  REFRESH_PIDS=()
  dir=$(refresh_cycle_dir)
  rm -rf "$dir"
  mkdir -p "$dir"
  for entry in "$@"; do
    name="${entry%%:*}"
    fn="${entry#*:}"
    REFRESH_NAMES+=("$name")
    _refresh_worker "$dir" "$name" "$fn" &
    REFRESH_PIDS+=("$!")
  done
}

_refresh_worker() {
  local dir="$1" name="$2" fn="$3" rc=0
  "$fn" >"$dir/${name}.out" 2>"$dir/${name}.err" || rc=$?
  _refresh_write_status "$dir" "$name" "$rc"
}

# Written via a rename so the foreground never reads a half-written status.
_refresh_write_status() {
  local dir="$1" name="$2" rc="$3"
  printf '%s' "$rc" >"$dir/${name}.status.part"
  mv -f "$dir/${name}.status.part" "$dir/${name}.status"
}

refresh_total() {
  printf '%s' "${#REFRESH_NAMES[@]}"
}

refresh_completed() {
  local dir file n=0
  dir=$(refresh_cycle_dir)
  for file in "$dir"/*.status; do
    if [[ -f $file ]]; then n=$(( n + 1 )); fi
  done
  printf '%s' "$n"
}

refresh_done() {
  (( $(refresh_completed) >= ${#REFRESH_NAMES[@]} ))
}

# refresh_expired <seconds> — true once the cycle has outlived its budget.
# 0 disables the deadline.
refresh_expired() {
  local limit="$1" now
  if (( limit <= 0 )); then return 1; fi
  now=$(date +%s)
  (( now - REFRESH_STARTED_AT >= limit ))
}

# refresh_abandon <seconds> — give up on whatever is still running: kill it,
# mark it failed, and replace its fragment with a timeout line. Partial output
# is discarded on purpose — half a section reads as truth.
refresh_abandon() {
  local limit="$1" dir i name pid
  dir=$(refresh_cycle_dir)
  for i in "${!REFRESH_NAMES[@]}"; do
    name="${REFRESH_NAMES[i]}"
    if [[ -f "$dir/${name}.status" ]]; then continue; fi
    pid="${REFRESH_PIDS[i]}"
    { kill "$pid" && wait "$pid"; } 2>/dev/null || true
    printf '  %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_KO" "${name} — refresh timed out after ${limit}s")" \
      >"$dir/${name}.out"
    log_error "refresh/${name}" "timed out after ${limit}s"
    _refresh_write_status "$dir" "$name" 124
  done
}

# refresh_output <name> — the component's frame fragment (empty if it produced
# nothing).
refresh_output() {
  local file
  file="$(refresh_cycle_dir)/${1}.out"
  if [[ -f $file ]]; then cat "$file"; fi
}

# refresh_failed — names of components whose render returned non-zero, one per
# line. A component that never reported counts as failed.
refresh_failed() {
  local dir name rc
  dir=$(refresh_cycle_dir)
  for name in "${REFRESH_NAMES[@]}"; do
    rc=1
    if [[ -f "$dir/${name}.status" ]]; then rc=$(<"$dir/${name}.status"); fi
    if [[ $rc != 0 ]]; then printf '%s\n' "$name"; fi
  done
}

# refresh_log_stderr — components own their error rendering, so anything on
# stderr is unexpected. It would have corrupted the frame; log it instead.
refresh_log_stderr() {
  local dir name file
  dir=$(refresh_cycle_dir)
  for name in "${REFRESH_NAMES[@]}"; do
    file="$dir/${name}.err"
    if [[ -s $file ]]; then log_error "refresh/${name}" "$(<"$file")"; fi
  done
}

refresh_cleanup() {
  local pid
  for pid in "${REFRESH_PIDS[@]}"; do
    { kill "$pid" && wait "$pid"; } 2>/dev/null || true
  done
  rm -rf "$REFRESH_SPOOL_ROOT"
}
