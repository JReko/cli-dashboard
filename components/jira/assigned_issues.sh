#!/usr/bin/env bash
# components/jira/assigned_issues.sh — non-closed Jira tickets assigned to me.
# In-progress first, then to-do. Columns: priority (hidden when every row is
# medium), status, clickable key,
# updated age (in-progress tickets go yellow past 7d, red past 14d — stale WIP
# is the smell), summary (truncated). A status breakdown bar sits above the
# table. Publishes wip_count / wip_stale to the pulse strip.

jira_assigned_issues_check() {
  local jql payload wip_keys count show_prio
  jql='assignee = currentUser() AND statusCategory != Done'

  # `--raw` gives status names only, no category. A second query for the
  # in-progress keys tells the two apart (Done is already filtered out, so
  # everything else is "new").
  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_jira_assigned_issues_payload)
    wip_keys=$(demo_jira_in_progress_keys_payload)
  elif ! _jira_assigned_issues_fetch '[]' issue list -q "$jql" --order-by updated --reverse --raw \
    || ! payload=$UI_REPLY \
    || ! _jira_assigned_issues_fetch '' issue list -q "$jql AND statusCategory = \"In Progress\"" \
      --plain --no-headers --columns key \
    || ! wip_keys=$UI_REPLY; then
    ui_feature_error "Assigned issues"
    return 1  # error line already rendered; the orchestrator collects the failure
  fi

  if ! require_json "jira/assigned_issues" "$payload"; then
    ui_feature_error "Assigned issues"
    return 1  # error line already rendered; the orchestrator collects the failure
  fi
  payload=$(jq --arg keys "$wip_keys" '
      ($keys | split("\n") | map(select(. != ""))) as $wip
      | map(.fields.status.statusCategory.key =
          (if [.key] | inside($wip) then "indeterminate" else "new" end))' <<<"$payload")

  count=$(jq 'length' <<<"$payload")
  _jira_assigned_issues_metrics "$payload"
  ui_feature_header "$UI_ICON_TICKET" "Assigned issues" "$count"
  if (( count == 0 )); then return 0; fi
  _jira_assigned_issues_breakdown "$payload" "$count"

  # A priority column where every row is medium (or unset) says nothing.
  show_prio=$(jq 'any(.[]; (.fields.priority.name // "None") | IN("Medium", "None") | not)' <<<"$payload")
  local -a heads=('Status' 'Key' 'Age:r' 'Summary:flex')
  if [[ $show_prio == true ]]; then heads=('P' "${heads[@]}"); fi

  local key summary priority status status_cat updated
  while IFS=$'\t' read -r key summary priority status status_cat updated; do
    _jira_assigned_issues_row "$show_prio" "$key" "$summary" "$priority" "$status" "$status_cat" "$updated"
  done < <(jq -r '
      def cat_rank: {"indeterminate": 0, "new": 1}[.fields.status.statusCategory.key // ""] // 2;
      sort_by(cat_rank) | .[] | [
        .key,
        .fields.summary,
        (.fields.priority.name // "None"),
        .fields.status.name,
        (.fields.status.statusCategory.key // "unknown"),
        .fields.updated
      ] | @tsv' <<<"$payload") \
    | ui_table 2 "$UI_WIDTH" "${heads[@]}"
}

# _jira_assigned_issues_fetch <empty_value> <jira args...> — UI_REPLY: stdout.
# jira-cli exits 1 for an empty result set just like for auth/network errors;
# the message is the only thing telling them apart, so match it (loosely) and
# return <empty_value>. Anything else is logged and returns 1.
_jira_assigned_issues_fetch() {
  local empty="$1" err_file err out
  shift
  err_file=$(mktemp)
  if out=$(jira "$@" 2>"$err_file"); then
    rm -f "$err_file"
    UI_REPLY=$out
    return 0
  fi
  err=$(<"$err_file"); rm -f "$err_file"
  if [[ $(_jira_strip_ansi "$err") == *[Nn]o\ result\ found* ]]; then
    UI_REPLY=$empty
    return 0
  fi
  log_error "jira/assigned_issues" "$err"
  return 1
}

# _jira_assigned_issues_metrics <payload> — in-progress count, and how many of
# those haven't moved in 7 days.
_jira_assigned_issues_metrics() {
  local updated wip=0 stale=0
  while IFS= read -r updated; do
    if [[ -z $updated ]]; then continue; fi
    wip=$(( wip + 1 ))
    ui_age "$updated"
    if (( UI_AGE_SECS >= 7 * UI_DAY )); then stale=$(( stale + 1 )); fi
  done < <(jq -r '.[] | select(.fields.status.statusCategory.key == "indeterminate") | .fields.updated' <<<"$1")
  ui_metric wip_count "$wip"
  ui_metric wip_stale "$stale"
}

# _jira_assigned_issues_breakdown <payload> <count> — one stacked bar, a
# segment per status (in table order), then a legend line.
_jira_assigned_issues_breakdown() {
  local payload="$1" total="$2" width=$(( UI_WIDTH - 2 ))
  local -a names=() cats=() counts=()
  local name cat n i seg used=0 avail bar='' legend='' color wip_shade=0 new_shade=0
  while IFS=$'\t' read -r name cat n; do
    names+=("$name"); cats+=("$cat"); counts+=("$n")
  done < <(jq -r '
      def cat_rank: {"indeterminate": 0, "new": 1}[.statusCategory.key // ""] // 2;
      [.[].fields.status] | sort_by(cat_rank)
      | reduce .[] as $s ([];
          if any(.[]; .name == $s.name) then map(if .name == $s.name then .n += 1 else . end)
          else . + [{name: $s.name, cat: ($s.statusCategory.key // "unknown"), n: 1}] end)
      | .[] | [.name, .cat, (.n|tostring)] | @tsv' <<<"$payload")

  avail=$(( width - (${#names[@]} - 1) ))
  for i in "${!names[@]}"; do
    case "${cats[i]}" in
      indeterminate)
        if (( wip_shade % 2 == 0 )); then color="$UI_INFO"; else color="$UI_LINK"; fi
        wip_shade=$(( wip_shade + 1 ))
        ;;
      done) color="$UI_OK" ;;
      *)
        if (( new_shade % 2 == 0 )); then color="$UI_SUBTLE"; else color="$UI_MUTED"; fi
        new_shade=$(( new_shade + 1 ))
        ;;
    esac
    if (( i == ${#names[@]} - 1 )); then
      seg=$(( avail - used ))
    else
      seg=$(( (counts[i] * avail + total / 2) / total ))
      if (( seg < 1 )); then seg=1; fi
    fi
    used=$(( used + seg ))
    ui_repeat "$UI_BAR_ON" "$seg"
    if [[ -n $bar ]]; then bar+=' '; fi
    bar+="$color$UI_REPLY$UI_RESET"
    if [[ -n $legend ]]; then legend+='   '; fi
    legend+="$color$UI_BOX_ON$UI_RESET $UI_MUTED${names[i]} ${counts[i]}$UI_RESET"
  done
  printf '  %s\n  %s\n' "$bar" "$legend"
}

_jira_assigned_issues_row() {
  local show_prio="$1" key="$2" summary="$3" priority="$4" status="$5" status_cat="$6" updated="$7"
  local prio_icon prio_color status_color age_color="$UI_MUTED"

  case "$priority" in
    Highest)     prio_icon="$UI_ICON_PRIO_HIGHEST"; prio_color="$UI_KO" ;;
    High)        prio_icon="$UI_ICON_PRIO_HIGH";    prio_color="$UI_WARN" ;;
    Medium)      prio_icon="$UI_ICON_PRIO_MEDIUM";  prio_color="$UI_MUTED" ;;
    Low|Lowest)  prio_icon="$UI_ICON_PRIO_LOW";     prio_color="$UI_MUTED" ;;
    *)           prio_icon='─';                     prio_color="$UI_MUTED" ;;
  esac

  case "$status_cat" in
    indeterminate) status_color="$UI_INFO" ;;
    done)          status_color="$UI_OK" ;;
    *)             status_color="$UI_MUTED" ;;
  esac

  ui_age "$updated"
  if [[ $status_cat == indeterminate ]]; then
    ui_age_color "$UI_AGE_SECS" $(( 7 * UI_DAY )) $(( 14 * UI_DAY ))
    age_color="$UI_REPLY"
  fi

  if [[ $show_prio == true ]]; then
    printf '%s\t' "$(ui_cell "$prio_color" "$prio_icon")"
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$(ui_cell "$status_color" "$status")" \
    "$(ui_cell "$UI_LINK" "$key" "${JIRA_HOST}/browse/${key}")" \
    "$(ui_cell "$age_color" "$UI_AGE_LABEL")" \
    "$(ui_cell "$UI_TEXT" "$summary")"
}

# jira-cli colorizes its messages even when stderr is a pipe, so strip SGR
# sequences before matching on the text.
_jira_strip_ansi() {
  printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g'
}
