#!/usr/bin/env bash
# components/github/prs_review_requested.sh — non-draft PRs awaiting our review,
# oldest first (longest wait = most urgent). Columns: state in words (CI
# failing / conflict / CI running, blank when healthy), repo, clickable PR#,
# age (yellow past 1d, red past 3d), author, title (truncated). Publishes review_count / review_oldest_secs to the
# pulse strip.

github_prs_review_requested_check() {
  local query payload count
  query='query {
    search(query: "is:pr is:open review-requested:@me draft:false", type: ISSUE, first: 50) {
      nodes {
        ... on PullRequest {
          number title url createdAt
          author { login }
          repository { nameWithOwner }
          mergeable
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
      }
    }
  }'

  if config_enabled DASHBOARD_DEMO; then
    payload=$(demo_github_prs_review_requested_payload)
  elif ! payload=$(gh api graphql -f query="$query" 2>&1); then
    log_error "github/prs_review_requested" "$payload"
    ui_feature_error "Awaiting my review"
    return 1
  fi

  count=$(jq '.data.search.nodes | length' <<<"$payload")
  ui_metric review_count "$count"
  if (( count > 0 )); then
    ui_age "$(jq -r '[.data.search.nodes[].createdAt] | min' <<<"$payload")"
    ui_metric review_oldest_secs "$UI_AGE_SECS"
  fi
  ui_feature_header "$UI_ICON_REVIEW" "Awaiting my review" "$count"
  if (( count == 0 )); then return 0; fi

  local repo number url ci merge created author title
  local -a parts
  while IFS=$'\t' read -r repo number url ci merge created author title; do
    parts=()
    if github_state_ci_failing "$ci"; then parts+=("$UI_REPLY"); fi
    if [[ $merge == CONFLICTING ]]; then parts+=("${UI_KO}conflict$UI_RESET"); fi
    if github_state_ci_running "$ci"; then parts+=("$UI_REPLY"); fi
    github_state_text ${parts[@]+"${parts[@]}"}
    ui_cell '' "$UI_REPLY"; printf '\t'
    ui_age "$created"
    ui_age_color "$UI_AGE_SECS" "$UI_DAY" $(( 3 * UI_DAY ))
    ui_cell "$UI_REPLY" "$UI_AGE_LABEL"; printf '\t'
    ui_cell "$UI_MUTED" "$repo"; printf '\t'
    ui_cell "$UI_LINK" "#$number" "$url"; printf '\t'
    ui_cell "$UI_SUBTLE" "@$author"; printf '\t'
    ui_cell "$UI_TEXT" "$title"; printf '\n'
  done < <(jq -r "$GITHUB_REPO_JQ_DEFS"'
      .data.search.nodes | common_owner(.) as $owner | sort_by(.createdAt) | .[] | [
      repo($owner),
      (.number|tostring),
      .url,
      (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
      .mergeable,
      .createdAt,
      (.author.login // "ghost"),
      .title
    ] | @tsv' <<<"$payload") \
    | ui_table 2 "$UI_WIDTH" 'State' 'Age:r' 'Repo:shrink' 'PR' 'Author:shrink' 'Title:flex'
}

