#!/usr/bin/env bash
# components/github/issues_assigned.sh — open issues assigned to me, scoped to
# GITHUB_ISSUES_REPO (owner/repo) when set, every repo otherwise.
#
# Sorted by what needs me: ai-problem-detected → blocked → untriaged (no state
# label) → ai-ready → ai-in-progress. Recently updated first within a group.
# Columns: state in words, issue type (bug / enhancement / task /
# investigation; hidden when no row has one), age since last update (yellow
# past 7d, red past 14d), repo (hidden when every row is in one repo),
# clickable issue#, title (truncated). Publishes issues_wip / issues_wip_stale
# (ai-in-progress, and those idle 7d+) to the pulse strip.

github_issues_assigned_check() {
  local query search payload count show_type show_repo
  # shellcheck disable=SC2016 # $q is a GraphQL variable, not a shell one
  query='query($q: String!) {
    search(query: $q, type: ISSUE, first: 50) {
      nodes {
        ... on Issue {
          number title url updatedAt
          repository { nameWithOwner }
          labels(first: 20) { nodes { name } }
        }
      }
    }
  }'
  search='is:issue is:open assignee:@me archived:false'
  if [[ -n ${GITHUB_ISSUES_REPO:-} ]]; then search+=" repo:$GITHUB_ISSUES_REPO"; fi

  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_github_issues_assigned_payload)
  elif ! payload=$(gh api graphql -f query="$query" -f q="$search" 2>&1); then
    log_error "github/issues_assigned" "$payload"
    ui_feature_error "My issues"
    return 1
  fi
  if ! require_json "github/issues_assigned" "$payload"; then
    ui_feature_error "My issues"
    return 1
  fi

  # One label per issue for its state and one for its type; jq picks the most
  # urgent state when several are set.
  payload=$(jq '.data.search.nodes | map(
      ([.labels.nodes[].name]) as $l
      | .state = (["ai-problem-detected", "blocked", "ai-ready", "ai-in-progress"]
          | map(select(. as $s | $l | index($s))) | .[0] // "")
      | .type = (["bug", "enhancement", "task", "investigation"]
          | map(select(. as $t | $l | index($t))) | .[0] // ""))' <<<"$payload")

  count=$(jq 'length' <<<"$payload")
  _github_issues_assigned_metrics "$payload"
  ui_feature_header "$UI_ICON_ISSUE" "My issues" "$count"
  if (( count == 0 )); then return 0; fi

  show_type=$(jq 'any(.[]; .type != "")' <<<"$payload")
  show_repo=$(jq '[.[].repository.nameWithOwner] | unique | length > 1' <<<"$payload")
  local -a heads=('State')
  if [[ $show_type == true ]]; then heads+=('Type'); fi
  heads+=('Age:r')
  if [[ $show_repo == true ]]; then heads+=('Repo:shrink'); fi
  heads+=('Issue' 'Title:flex')

  local state type updated repo number url title
  while IFS=$'\t' read -r state type updated repo number url title; do
    _github_issues_assigned_row "$show_type" "$show_repo" \
      "$state" "$type" "$updated" "$repo" "$number" "$url" "$title"
  done < <(jq -r "$GITHUB_REPO_JQ_DEFS"'
      def rank: {"ai-problem-detected": 0, "blocked": 1, "": 2, "ai-ready": 3, "ai-in-progress": 4}[.state];
      common_owner(.) as $owner
      | sort_by(.updatedAt) | reverse | sort_by(rank) | .[] | [
        (if .state == "" then "-" else .state end),
        (if .type == "" then "-" else .type end),
        .updatedAt,
        repo($owner),
        (.number|tostring),
        .url,
        .title
      ] | @tsv' <<<"$payload") \
    | ui_table 2 "$UI_WIDTH" "${heads[@]}"
}

# _github_issues_assigned_metrics <payload> — issues an agent is working on,
# and how many of those haven't moved in 7 days.
_github_issues_assigned_metrics() {
  local updated wip=0 stale=0
  while IFS= read -r updated; do
    if [[ -z $updated ]]; then continue; fi
    wip=$(( wip + 1 ))
    ui_age "$updated"
    if (( UI_AGE_SECS >= 7 * UI_DAY )); then stale=$(( stale + 1 )); fi
  done < <(jq -r '.[] | select(.state == "ai-in-progress") | .updatedAt' <<<"$1")
  ui_metric issues_wip "$wip"
  ui_metric issues_wip_stale "$stale"
}

# `-` stands in for empty fields: bash `read` collapses consecutive tabs.
_github_issues_assigned_row() {
  local show_type="$1" show_repo="$2" state="$3" type="$4" updated="$5"
  local repo="$6" number="$7" url="$8" title="$9" label='' color="$UI_MUTED"

  case "$state" in
    ai-problem-detected) label='needs me';      color="$UI_KO" ;;
    blocked)             label='blocked';       color="$UI_KO" ;;
    ai-ready)            label='ai-ready';      color="$UI_OK" ;;
    ai-in-progress)      label='agent working'; color="$UI_INFO" ;;
  esac
  ui_cell "$color" "$label"; printf '\t'

  if [[ $show_type == true ]]; then
    color="$UI_SUBTLE"
    if [[ $type == bug ]]; then color="$UI_WARN"; fi
    if [[ $type == - ]]; then type=''; fi
    ui_cell "$color" "$type"; printf '\t'
  fi

  ui_age "$updated"
  ui_age_color "$UI_AGE_SECS" $(( 7 * UI_DAY )) $(( 14 * UI_DAY ))
  ui_cell "$UI_REPLY" "$UI_AGE_LABEL"; printf '\t'

  if [[ $show_repo == true ]]; then
    ui_cell "$UI_MUTED" "$repo"; printf '\t'
  fi
  ui_cell "$UI_LINK" "#$number" "$url"; printf '\t'
  ui_cell "$UI_TEXT" "$title"; printf '\n'
}
