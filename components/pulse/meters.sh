#!/usr/bin/env bash
# components/pulse/meters.sh — one meter per number worth watching: label and
# value, a gradient bar, a caption. Bars fill against a budget, so a full bar
# means "this is too much", not "this is the max seen". A meter whose source is
# off (or failed) is left out rather than shown as zero.

PULSE_METER_MIN=20

# Budgets: the count at which a bar is full.
PULSE_BUDGET_REVIEW=8
PULSE_BUDGET_WIP=4
PULSE_BUDGET_BREW=20

# _pulse_meter <width> <label> <value> <filled> <cells_of> <caption> — three
# lines. filled/cells_of is the bar ratio; caption may carry colors.
_pulse_meter() {
  local width="$1" label="$2" value="$3" filled="$4" of="$5" caption="$6" gap cells
  gap=$(( width - ${#label} - ${#value} ))
  if (( gap < 1 )); then gap=1; fi
  printf '%s%s%s%*s%s%s%s\n' "$UI_SUBTLE" "$label" "$UI_RESET" "$gap" '' "$UI_BOLD$UI_TEXT" "$value" "$UI_RESET"
  cells=0
  if (( of > 0 )); then cells=$(( (filled * width + of - 1) / of )); fi
  ui_bar "$cells" "$width"
  printf '%s\n' "$UI_REPLY"
  printf '%s\n' "$caption"
}

# _pulse_has <key...> — every key was published this cycle.
_pulse_has() {
  local key
  for key in "$@"; do
    if [[ -z ${PULSE_METRICS[$key]+set} ]]; then return 1; fi
  done
}

# _pulse_sum <key...> — UI_REPLY: sum of the published keys among them, or
# empty when none were.
_pulse_sum() {
  local key sum=''
  for key in "$@"; do
    if [[ -n ${PULSE_METRICS[$key]+set} ]]; then sum=$(( ${sum:-0} + PULSE_METRICS[$key] )); fi
  done
  UI_REPLY="$sum"
}

# pulse_meters_render <width> — meters side by side in one row, or one per line
# when the row doesn't fit.
pulse_meters_render() {
  local width="$1" m="$UI_MUTED" r="$UI_RESET" caption n
  local -a blocks=()

  if _pulse_has review_count; then
    n=${PULSE_METRICS[review_count]}
    caption="${m}queue clear${r}"
    if (( n > 0 )) && _pulse_has review_oldest_secs; then
      ui_age_label "${PULSE_METRICS[review_oldest_secs]}"
      local label="$UI_REPLY"
      ui_age_color "${PULSE_METRICS[review_oldest_secs]}" "$UI_DAY" $(( 3 * UI_DAY ))
      caption="${m}oldest ${r}${UI_REPLY}${label}${r}"
    fi
    blocks+=("review|PRs to review|$n|$n|$PULSE_BUDGET_REVIEW|$caption")
  fi

  if _pulse_has mine_total mine_blocked; then
    local total=${PULSE_METRICS[mine_total]} blocked=${PULSE_METRICS[mine_blocked]}
    local ready=${PULSE_METRICS[mine_ready]:-0}
    caption="${m}of ${total} open${r}"
    if (( ready > 0 )); then caption+="${m} · ${r}${UI_OK}${ready} ready${r}"; fi
    blocks+=("mine|My PRs blocked|$blocked|$blocked|$total|$caption")
  fi

  if _pulse_has wip_count; then
    local wip=${PULSE_METRICS[wip_count]} stale=${PULSE_METRICS[wip_stale]:-0}
    caption="${m}none stale${r}"
    if (( stale > 0 )); then caption="${UI_WARN}${stale} stale${r}${m} > 7d${r}"; fi
    blocks+=("wip|Jira in progress|$wip|$wip|$PULSE_BUDGET_WIP|$caption")
  fi

  _pulse_sum brew_formulae_outdated brew_casks_outdated
  if [[ -n $UI_REPLY ]]; then
    local outdated=$UI_REPLY
    _pulse_sum brew_formulae_major brew_casks_major
    local major=${UI_REPLY:-0}
    caption="${m}no major bumps${r}"
    if (( major > 0 )); then caption="${UI_WARN}${major} major${r}"; fi
    blocks+=("brew|Brew outdated|$outdated|$outdated|$PULSE_BUDGET_BREW|$caption")
  fi

  if (( ${#blocks[@]} == 0 )); then
    printf '%snothing to summarise%s\n' "$m" "$r"
    return 0
  fi

  local cols=$(( (width + 3) / (PULSE_METER_MIN + 3) )) col_width i j k
  if (( cols < ${#blocks[@]} )); then
    _pulse_meters_list "$width" "${blocks[@]}"
    return 0
  fi
  col_width=$(( (width - 3 * (${#blocks[@]} - 1)) / ${#blocks[@]} ))

  local -a lines=('' '' '') parts
  for i in "${!blocks[@]}"; do
    IFS='|' read -r _ a b c d e <<<"${blocks[i]}"
    mapfile -t parts < <(_pulse_meter "$col_width" "$a" "$b" "$c" "$d" "$e")
    for k in 0 1 2; do
      if (( i > 0 )); then lines[k]+='   '; fi
      _ui_visible_len "${parts[k]}"
      printf -v j '%*s' $(( col_width - UI_REPLY )) ''
      lines[k]+="${parts[k]}$j"
    done
  done
  for k in 0 1 2; do printf '%s\n' "${lines[k]%"${lines[k]##*[! ]}"}"; done
}

# _pulse_meters_list <width> <block>... — too narrow for one row: one meter per
# line, "label  value  bar  caption", columns aligned.
_pulse_meters_list() {
  local width="$1"; shift
  local block label_w=0 value_w=0 caption_w=0 bar_w a b c d e cells pad
  for block in "$@"; do
    IFS='|' read -r _ a b c d e <<<"$block"
    if (( ${#a} > label_w )); then label_w=${#a}; fi
    if (( ${#b} > value_w )); then value_w=${#b}; fi
    _ui_visible_len "$e"
    if (( UI_REPLY > caption_w )); then caption_w=$UI_REPLY; fi
  done
  bar_w=$(( width - label_w - value_w - caption_w - 6 ))
  if (( bar_w > 24 )); then bar_w=24; fi
  if (( bar_w < 6 )); then bar_w=6; fi
  for block in "$@"; do
    IFS='|' read -r _ a b c d e <<<"$block"
    cells=0
    if (( d > 0 )); then cells=$(( (c * bar_w + d - 1) / d )); fi
    ui_bar "$cells" "$bar_w"
    printf -v pad '%*s' $(( label_w - ${#a} )) ''
    printf '%s%s%s%s  %s%*s%s  %s  %s\n' "$UI_SUBTLE" "$a" "$UI_RESET" "$pad" \
      "$UI_BOLD$UI_TEXT" "$value_w" "$b" "$UI_RESET" "$UI_REPLY" "$e"
  done
}
