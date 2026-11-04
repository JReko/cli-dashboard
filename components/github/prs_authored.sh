#!/usr/bin/env bash
# components/github/prs_authored.sh — open PRs I authored (drafts included),
# sorted by what needs me: blocked first (changes requested, red CI, conflict),
# then ready to merge, then waiting on others, then drafts.
# Columns: state in words (what blocks it, "ready to merge", or where review
# stands), repo, clickable PR#, age (yellow past 3d, red past 7d), title
# (truncated). Drafts are dimmed and say "draft". Publishes mine_total /
# mine_blocked / mine_ready to the pulse strip.

# Shared by the sort and the pulse counts: 0 blocked on me, 1 ready to merge,
# 2 waiting on others, 3 draft.
_GITHUB_PRS_AUTHORED_JQ_DEFS='
  def ci: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE");
  def approved: ([.latestReviews.nodes[] | select(.state == "APPROVED")] | length);
  def rank:
    if .isDraft then 3
    elif .reviewDecision == "CHANGES_REQUESTED"
      or (ci | IN("FAILURE", "ERROR"))
      or .mergeable == "CONFLICTING" then 0
    elif (.reviewDecision == "APPROVED"
      or (.reviewDecision == null and approved > 0 and .reviewRequests.totalCount == 0))
      and (ci | IN("SUCCESS", "NONE")) then 1
    else 2 end;
'

github_prs_authored_check() {
  local query payload count
  query='query {
    search(query: "is:pr is:open author:@me", type: ISSUE, first: 50) {
      nodes {
        ... on PullRequest {
          number title url createdAt isDraft
          repository { nameWithOwner }
          mergeable
          reviewDecision
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          latestReviews(first: 50) { nodes { state } }
          reviewRequests(first: 1) { totalCount }
        }
      }
    }
  }'

  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_github_prs_authored_payload)
  elif ! payload=$(gh api graphql -f query="$query" 2>&1); then
    log_error "github/prs_authored" "$payload"
    ui_feature_error "My PRs"
    return 1
  fi

  count=$(jq '.data.search.nodes | length' <<<"$payload")
  local total_open blocked ready
  read -r total_open blocked ready < <(jq -r "$_GITHUB_PRS_AUTHORED_JQ_DEFS"'
      [.data.search.nodes[] | rank]
      | [map(select(. < 3)) | length, (map(select(. == 0)) | length), (map(select(. == 1)) | length)]
      | @tsv' <<<"$payload")
  ui_metric mine_total "$total_open"
  ui_metric mine_blocked "$blocked"
  ui_metric mine_ready "$ready"
  ui_feature_header "$UI_ICON_PR" "My PRs" "$count"
  if (( count == 0 )); then return 0; fi

  local rank repo number url ci merge decision approved total created title
  while IFS=$'\t' read -r rank repo number url ci merge decision approved total created title; do
    _github_prs_authored_row "$rank" "$repo" "$number" "$url" "$ci" "$merge" \
      "$decision" "$approved" "$total" "$created" "$title"
  done < <(jq -r "$_GITHUB_PRS_AUTHORED_JQ_DEFS$GITHUB_REPO_JQ_DEFS"'
      .data.search.nodes
      | common_owner(.) as $owner
      | sort_by([rank, (.createdAt | fromdateiso8601 | -.)])
      | .[] | [
        (rank|tostring),
        repo($owner),
        (.number|tostring),
        .url,
        ci,
        .mergeable,
        (.reviewDecision // "NONE"),
        (approved|tostring),
        ((.latestReviews.nodes | length) + .reviewRequests.totalCount | tostring),
        .createdAt,
        .title
      ] | @tsv' <<<"$payload") \
    | ui_table 2 "$UI_WIDTH" 'State' 'Age:r' 'Repo:shrink' 'PR' 'Title:flex'
}

# _github_prs_authored_row <rank> ... — rank as in the jq defs above decides
# what the State column says.
_github_prs_authored_row() {
  local rank="$1" repo="$2" number="$3" url="$4" ci="$5" merge="$6"
  local decision="$7" approved="$8" total="$9" created="${10}" title="${11}"
  local -a parts=()
  local muted_row=false text_color="$UI_TEXT" age_color

  case "$rank" in
    0)
      if [[ $decision == CHANGES_REQUESTED ]]; then parts+=("${UI_KO}changes requested$UI_RESET"); fi
      if github_state_ci_failing "$ci"; then parts+=("$UI_REPLY"); fi
      if [[ $merge == CONFLICTING ]]; then parts+=("${UI_KO}conflict$UI_RESET"); fi
      ;;
    1) parts+=("${UI_OK}ready to merge$UI_RESET") ;;
    2)
      if github_state_ci_running "$ci"; then parts+=("$UI_REPLY"); fi
      # reviewDecision is only set when branch protection requires reviews;
      # otherwise the counts are all there is.
      if (( total == 0 )); then
        parts+=("${UI_WARN}no reviewers$UI_RESET")
      elif (( approved == 0 )); then
        parts+=("${UI_MUTED}awaiting review$UI_RESET")
      else
        parts+=("${UI_MUTED}${approved}/${total} approved$UI_RESET")
      fi
      ;;
    *) parts+=("${UI_MUTED}draft$UI_RESET"); muted_row=true ;;
  esac
  github_state_text "${parts[@]}"
  local state="$UI_REPLY"

  ui_age "$created"
  ui_age_color "$UI_AGE_SECS" $(( 3 * UI_DAY )) $(( 7 * UI_DAY ))
  age_color="$UI_REPLY"
  if [[ $muted_row == true ]]; then
    age_color="$UI_MUTED"; text_color="$UI_MUTED"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(ui_cell '' "$state")" \
    "$(ui_cell "$age_color" "$UI_AGE_LABEL")" \
    "$(ui_cell "$UI_MUTED" "$repo")" \
    "$(ui_cell "$UI_LINK" "#$number" "$url")" \
    "$(ui_cell "$text_color" "$title")"
}
