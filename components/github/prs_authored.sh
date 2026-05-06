#!/usr/bin/env bash
# components/github/prs_authored.sh — open PRs I authored (drafts included).
# Per row: CI icon, mergeable icon, repo, clickable PR#, age, review state icon,
# approved/total reviewer count, title. Drafts are dimmed entirely.

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
    printf '  %s PRs I opened %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "ERROR: $payload")"
    return 1
  fi

  count=$(jq '.data.search.nodes | length' <<<"$payload")
  printf '  %s PRs I opened %s %s\n' \
    "$(ui_paint "$UI_ACCENT" "$UI_ICON_PR")" \
    "$(ui_paint "$UI_MUTED" '·')" \
    "$(ui_paint "$UI_TEXT" "$count")"

  if (( count == 0 )); then
    printf '    %s\n' "$(ui_paint "$UI_MUTED" '(none)')"
    return 0
  fi

  # Buffer rows so we can right-pad columns to the widest value in the batch.
  local rows=() repo number url ci merge is_draft review_decision approved total created title
  local repo_w=0 pr_w=0 age_w=0 counts_w=0 age pr_visible counts
  while IFS=$'\t' read -r repo number url ci merge is_draft review_decision approved total created title; do
    age=$(_github_prs_authored_age "$created")
    pr_visible="#$number"
    counts="$approved/$total"
    rows+=("$repo"$'\t'"$number"$'\t'"$url"$'\t'"$ci"$'\t'"$merge"$'\t'"$is_draft"$'\t'"$review_decision"$'\t'"$approved"$'\t'"$total"$'\t'"$age"$'\t'"$title")
    (( ${#repo}       > repo_w   )) && repo_w=${#repo}
    (( ${#pr_visible} > pr_w     )) && pr_w=${#pr_visible}
    (( ${#age}        > age_w    )) && age_w=${#age}
    (( ${#counts}     > counts_w )) && counts_w=${#counts}
  done < <(jq -r '.data.search.nodes[] | [
      .repository.nameWithOwner,
      (.number|tostring),
      .url,
      (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
      .mergeable,
      (.isDraft|tostring),
      (.reviewDecision // "NONE"),
      ([.latestReviews.nodes[] | select(.state == "APPROVED")] | length | tostring),
      (
        (.latestReviews.nodes | length) + (.reviewRequests.totalCount) | tostring
      ),
      .createdAt,
      .title
    ] | @tsv' <<<"$payload")

  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r repo number url ci merge is_draft review_decision approved total age title <<<"$row"
    _github_prs_authored_row \
      "$repo_w" "$pr_w" "$age_w" "$counts_w" \
      "$repo" "$number" "$url" "$ci" "$merge" \
      "$is_draft" "$review_decision" "$approved" "$total" "$age" "$title"
  done
}

_github_prs_authored_row() {
  local repo_w="$1" pr_w="$2" age_w="$3" counts_w="$4"
  local repo="$5" number="$6" url="$7" ci="$8" merge="$9"
  local is_draft="${10}" review_decision="${11}" approved="${12}" total="${13}"
  local age="${14}" title="${15}"
  local ci_icon ci_color merge_icon merge_color rev_icon rev_color
  local repo_color age_color counts_color title_color
  local pr_visible pr_link

  case "$ci" in
    SUCCESS)          ci_icon="$UI_ICON_OK";      ci_color="$UI_OK" ;;
    PENDING|EXPECTED) ci_icon="$UI_ICON_PENDING"; ci_color="$UI_WARN" ;;
    NONE|'')          ci_icon='─';                ci_color="$UI_MUTED" ;;
    *)                ci_icon="$UI_ICON_KO";      ci_color="$UI_KO" ;;
  esac
  case "$merge" in
    MERGEABLE)   merge_icon="$UI_ICON_MERGE"; merge_color="$UI_OK" ;;
    CONFLICTING) merge_icon="$UI_ICON_KO";    merge_color="$UI_KO" ;;
    *)           merge_icon="$UI_ICON_WARN";  merge_color="$UI_WARN" ;;
  esac
  case "$review_decision" in
    APPROVED)          rev_icon="$UI_ICON_OK";      rev_color="$UI_OK" ;;
    CHANGES_REQUESTED) rev_icon="$UI_ICON_KO";      rev_color="$UI_KO" ;;
    REVIEW_REQUIRED)   rev_icon="$UI_ICON_PENDING"; rev_color="$UI_WARN" ;;
    *)                 rev_icon='─';                rev_color="$UI_MUTED" ;;
  esac

  repo_color="$UI_MUTED"
  age_color="$UI_MUTED"
  counts_color="$UI_SUBTLE"
  title_color="$UI_TEXT"

  if [[ "$is_draft" == "true" ]]; then
    ci_color="$UI_MUTED"
    merge_color="$UI_MUTED"
    rev_color="$UI_MUTED"
    counts_color="$UI_MUTED"
    title_color="$UI_MUTED"
  fi

  printf -v pr_visible '%-*s' "$pr_w" "#$number"
  pr_link=$(ui_hyperlink "$url" "$pr_visible")

  printf '    %s  %s  %s%-*s%s  %s%s%s  %s%-*s%s  %s  %s%-*s%s  %s%s%s\n' \
    "$(ui_paint "$ci_color" "$ci_icon")" \
    "$(ui_paint "$merge_color" "$merge_icon")" \
    "$repo_color"   "$repo_w"   "$repo"            "$UI_RESET" \
    "$UI_LINK"                  "$pr_link"         "$UI_RESET" \
    "$age_color"    "$age_w"    "$age"             "$UI_RESET" \
    "$(ui_paint "$rev_color" "$rev_icon")" \
    "$counts_color" "$counts_w" "$approved/$total" "$UI_RESET" \
    "$title_color"              "$title"           "$UI_RESET"
}

_github_prs_authored_age() {
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
