#!/usr/bin/env bash
# components/jira/assigned_issues.sh — non-closed Jira tickets assigned to me.
# Per row: priority icon, status, clickable issue key, updated age, summary.
# Columns are padded to the widest value in the batch.

jira_assigned_issues_check() {
  local jql payload count err_file err
  jql='assignee = currentUser() AND statusCategory != Done'

  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_jira_assigned_issues_payload)
  else
    err_file=$(mktemp)
    if ! payload=$(jira issue list -q "$jql" --order-by updated --reverse --raw 2>"$err_file"); then
      err=$(<"$err_file"); rm -f "$err_file"
      # An empty result set is not a failure, but jira-cli exits 1 for it just
      # like it does for auth/network errors. The message is the only thing
      # telling them apart, so match it (loosely) and fall through with an
      # empty array; anything else is a real error.
      if [[ $(_jira_strip_ansi "$err") == *[Nn]o\ result\ found* ]]; then
        payload='[]'
      else
        log_error "jira/assigned_issues" "$err"
        printf '  %s Assigned issues %s %s\n' \
          "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
          "$(ui_paint "$UI_MUTED" '·')" \
          "$(ui_paint "$UI_KO" "ERROR (see $(log_path_display))")"
        return 1  # error line already rendered; the orchestrator collects the failure
      fi
    else
      rm -f "$err_file"
    fi
  fi

  if ! require_json "jira/assigned_issues" "$payload"; then
    printf '  %s Assigned issues %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "ERROR (see $(log_path_display))")"
    return 1  # error line already rendered; the orchestrator collects the failure
  fi

  count=$(jq 'length' <<<"$payload")
  printf '  %s Assigned issues %s %s\n' \
    "$(ui_paint "$UI_ACCENT" "$UI_ICON_TICKET")" \
    "$(ui_paint "$UI_MUTED" '·')" \
    "$(ui_paint "$UI_TEXT" "$count")"

  if (( count == 0 )); then
    printf '    %s\n' "$(ui_paint "$UI_MUTED" '(none)')"
    return 0
  fi

  local rows=() key summary priority status status_cat updated age
  local key_w=0 status_w=0 age_w=0
  while IFS=$'\t' read -r key summary priority status status_cat updated; do
    age=$(_jira_assigned_issues_age "$updated")
    rows+=("$key"$'\t'"$summary"$'\t'"$priority"$'\t'"$status"$'\t'"$status_cat"$'\t'"$age")
    (( ${#key}    > key_w    )) && key_w=${#key}
    (( ${#status} > status_w )) && status_w=${#status}
    (( ${#age}    > age_w    )) && age_w=${#age}
  done < <(jq -r '.[] | [
      .key,
      .fields.summary,
      (.fields.priority.name // "None"),
      .fields.status.name,
      (.fields.status.statusCategory.key // "unknown"),
      .fields.updated
    ] | @tsv' <<<"$payload")

  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r key summary priority status status_cat age <<<"$row"
    _jira_assigned_issues_row \
      "$key_w" "$status_w" "$age_w" \
      "$key" "$summary" "$priority" "$status" "$status_cat" "$age"
  done
}

_jira_assigned_issues_row() {
  local key_w="$1" status_w="$2" age_w="$3"
  local key="$4" summary="$5" priority="$6" status="$7" status_cat="$8" age="$9"
  local prio_icon prio_color status_color key_visible key_link

  case "$priority" in
    Highest)        prio_icon="$UI_ICON_WARN";    prio_color="$UI_KO" ;;
    High)           prio_icon="$UI_ICON_WARN";    prio_color="$UI_WARN" ;;
    Medium)         prio_icon="$UI_ICON_PENDING"; prio_color="$UI_INFO" ;;
    Low|Lowest|None|'') prio_icon='─';            prio_color="$UI_MUTED" ;;
    *)              prio_icon="$UI_ICON_PENDING"; prio_color="$UI_MUTED" ;;
  esac

  case "$status_cat" in
    new)           status_color="$UI_MUTED" ;;
    indeterminate) status_color="$UI_INFO" ;;
    done)          status_color="$UI_OK" ;;
    *)             status_color="$UI_TEXT" ;;
  esac

  printf -v key_visible '%-*s' "$key_w" "$key"
  key_link=$(ui_hyperlink "${JIRA_HOST}/browse/${key}" "$key_visible")

  printf '    %s  %s%-*s%s  %s%s%s  %s%-*s%s  %s%s%s\n' \
    "$(ui_paint "$prio_color" "$prio_icon")" \
    "$status_color" "$status_w" "$status"  "$UI_RESET" \
    "$UI_LINK"                  "$key_link" "$UI_RESET" \
    "$UI_MUTED"     "$age_w"    "$age"      "$UI_RESET" \
    "$UI_TEXT"                  "$summary"  "$UI_RESET"
}

_jira_assigned_issues_age() {
  local ts="$1" now started diff
  now=$(date +%s)
  if ! started=$(gdate -d "$ts" +%s 2>/dev/null); then
    printf '?'
    return
  fi
  diff=$(( now - started ))
  if   (( diff < 3600 ));  then printf '%dm' "$(( diff / 60 ))"
  elif (( diff < 86400 )); then printf '%dh' "$(( diff / 3600 ))"
  else                          printf '%dd' "$(( diff / 86400 ))"
  fi
}

# jira-cli colorizes its messages even when stderr is a pipe, so strip SGR
# sequences before matching on the text.
_jira_strip_ansi() {
  printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g'
}
