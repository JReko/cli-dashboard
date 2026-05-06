#!/usr/bin/env bash
# components/github/prs_review_requested.sh — non-draft PRs awaiting our review.
# Per row: CI status icon, mergeable icon, repo, clickable PR#, created age,
# author, title. Columns are padded to the widest value in the batch.

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
    printf '  %s PRs awaiting review %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "ERROR: $payload")"
    return 1
  fi

  count=$(jq '.data.search.nodes | length' <<<"$payload")
  printf '  %s PRs awaiting review %s %s\n' \
    "$(ui_paint "$UI_ACCENT" "$UI_ICON_PR")" \
    "$(ui_paint "$UI_MUTED" '·')" \
    "$(ui_paint "$UI_TEXT" "$count")"

  if (( count == 0 )); then
    printf '    %s\n' "$(ui_paint "$UI_MUTED" '(none)')"
    return 0
  fi

  # Buffer rows so we can right-pad columns to the widest value in the batch.
  local rows=() repo number url ci merge created author title
  local repo_w=0 pr_w=0 age_w=0 author_w=0 age pr_visible
  local author_at
  while IFS=$'\t' read -r repo number url ci merge created author title; do
    age=$(_github_prs_review_requested_age "$created")
    pr_visible="#$number"
    author_at="@$author"
    rows+=("$repo"$'\t'"$number"$'\t'"$url"$'\t'"$ci"$'\t'"$merge"$'\t'"$age"$'\t'"$author"$'\t'"$title")
    (( ${#repo}        > repo_w   )) && repo_w=${#repo}
    (( ${#pr_visible}  > pr_w     )) && pr_w=${#pr_visible}
    (( ${#age}         > age_w    )) && age_w=${#age}
    (( ${#author_at}   > author_w )) && author_w=${#author_at}
  done < <(jq -r '.data.search.nodes[] | [
      .repository.nameWithOwner,
      (.number|tostring),
      .url,
      (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
      .mergeable,
      .createdAt,
      (.author.login // "ghost"),
      .title
    ] | @tsv' <<<"$payload")

  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r repo number url ci merge age author title <<<"$row"
    _github_prs_review_requested_row \
      "$repo_w" "$pr_w" "$age_w" "$author_w" \
      "$repo" "$number" "$url" "$ci" "$merge" "$age" "$author" "$title"
  done
}

_github_prs_review_requested_row() {
  local repo_w="$1" pr_w="$2" age_w="$3" author_w="$4"
  local repo="$5" number="$6" url="$7" ci="$8" merge="$9"
  local age="${10}" author="${11}" title="${12}"
  local ci_icon ci_color merge_icon merge_color pr_visible pr_link
  local author_with_at="@$author"

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

  printf -v pr_visible '%-*s' "$pr_w" "#$number"
  pr_link=$(ui_hyperlink "$url" "$pr_visible")

  printf '    %s  %s  %s%-*s%s  %s%s%s  %s%-*s%s  %s%-*s%s  %s%s%s\n' \
    "$(ui_paint "$ci_color" "$ci_icon")" \
    "$(ui_paint "$merge_color" "$merge_icon")" \
    "$UI_MUTED"  "$repo_w"   "$repo"            "$UI_RESET" \
    "$UI_LINK"               "$pr_link"         "$UI_RESET" \
    "$UI_MUTED"  "$age_w"    "$age"             "$UI_RESET" \
    "$UI_SUBTLE" "$author_w" "$author_with_at"  "$UI_RESET" \
    "$UI_TEXT"               "$title"           "$UI_RESET"
}

_github_prs_review_requested_age() {
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
