#!/usr/bin/env bash
# components/github/prs_authored.sh — open PRs I authored (drafts included).
# Header row names the columns. Per row: CI icon, mergeable icon, repo,
# clickable PR#, age, review state icon, approved/total reviewer count, title.
# Drafts are dimmed entirely.

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
    printf '  %s PRs I opened %s %s\n' \
      "$(ui_paint "$UI_KO" "$UI_ICON_KO")" \
      "$(ui_paint "$UI_MUTED" '·')" \
      "$(ui_paint "$UI_KO" "ERROR (see $(log_path_display))")"
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
  # Widths start at the header label length so the header always fits.
  local rows=() repo number url ci merge is_draft review_decision requested approved total created title
  local ci_w=2 merge_w=5 repo_w=4 pr_w=2 age_w=3 rev_w=6 counts_w=4 age pr_visible counts
  while IFS=$'\t' read -r repo number url ci merge is_draft review_decision requested approved total created title; do
    age=$(_github_prs_authored_age "$created")
    pr_visible="#$number"
    counts="$approved/$total"
    rows+=("$repo"$'\t'"$number"$'\t'"$url"$'\t'"$ci"$'\t'"$merge"$'\t'"$is_draft"$'\t'"$review_decision"$'\t'"$requested"$'\t'"$approved"$'\t'"$total"$'\t'"$age"$'\t'"$title")
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
      (.reviewRequests.totalCount|tostring),
      ([.latestReviews.nodes[] | select(.state == "APPROVED")] | length | tostring),
      (
        (.latestReviews.nodes | length) + (.reviewRequests.totalCount) | tostring
      ),
      .createdAt,
      .title
    ] | @tsv' <<<"$payload")

  _github_prs_authored_header \
    "$ci_w" "$merge_w" "$repo_w" "$pr_w" "$age_w" "$rev_w" "$counts_w"

  local row
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r repo number url ci merge is_draft review_decision requested approved total age title <<<"$row"
    _github_prs_authored_row \
      "$ci_w" "$merge_w" "$repo_w" "$pr_w" "$age_w" "$rev_w" "$counts_w" \
      "$repo" "$number" "$url" "$ci" "$merge" \
      "$is_draft" "$review_decision" "$requested" "$approved" "$total" "$age" "$title"
  done
}

# _github_prs_authored_cell <width> <color> <text> — paint text, then pad to
# width by character count (printf %-*s pads by bytes, which breaks on glyphs).
_github_prs_authored_cell() {
  local width="$1" color="$2" text="$3" pad=''
  local pad_len=$(( width - ${#text} ))
  if (( pad_len > 0 )); then
    printf -v pad '%*s' "$pad_len" ''
  fi
  printf '%s%s' "$(ui_paint "$color" "$text")" "$pad"
}

_github_prs_authored_header() {
  local ci_w="$1" merge_w="$2" repo_w="$3" pr_w="$4" age_w="$5" rev_w="$6" counts_w="$7"
  printf '    %s  %s  %s  %s  %s  %s  %s  %s\n' \
    "$(_github_prs_authored_cell "$ci_w"     "$UI_MUTED" 'CI')" \
    "$(_github_prs_authored_cell "$merge_w"  "$UI_MUTED" 'Merge')" \
    "$(_github_prs_authored_cell "$repo_w"   "$UI_MUTED" 'Repo')" \
    "$(_github_prs_authored_cell "$pr_w"     "$UI_MUTED" 'PR')" \
    "$(_github_prs_authored_cell "$age_w"    "$UI_MUTED" 'Age')" \
    "$(_github_prs_authored_cell "$rev_w"    "$UI_MUTED" 'Review')" \
    "$(_github_prs_authored_cell "$counts_w" "$UI_MUTED" 'Appr')" \
    "$(ui_paint "$UI_MUTED" 'Title')"
}

_github_prs_authored_row() {
  local ci_w="$1" merge_w="$2" repo_w="$3" pr_w="$4" age_w="$5" rev_w="$6" counts_w="$7"
  local repo="$8" number="$9" url="${10}" ci="${11}" merge="${12}"
  local is_draft="${13}" review_decision="${14}" requested="${15}"
  local approved="${16}" total="${17}" age="${18}" title="${19}"
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
  # reviewDecision is only set when branch protection requires reviews. On
  # unprotected branches fall back to pending review requests.
  case "$review_decision" in
    APPROVED)          rev_icon="$UI_ICON_OK";     rev_color="$UI_OK" ;;
    CHANGES_REQUESTED) rev_icon="$UI_ICON_KO";     rev_color="$UI_KO" ;;
    REVIEW_REQUIRED)   rev_icon="$UI_ICON_REVIEW"; rev_color="$UI_WARN" ;;
    *)
      if (( requested > 0 )); then
        rev_icon="$UI_ICON_REVIEW"; rev_color="$UI_WARN"
      else
        rev_icon='─';               rev_color="$UI_MUTED"
      fi
      ;;
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

  printf '    %s  %s  %s  %s%s%s  %s  %s  %s  %s\n' \
    "$(_github_prs_authored_cell "$ci_w"     "$ci_color"     "$ci_icon")" \
    "$(_github_prs_authored_cell "$merge_w"  "$merge_color"  "$merge_icon")" \
    "$(_github_prs_authored_cell "$repo_w"   "$repo_color"   "$repo")" \
    "$UI_LINK" "$pr_link" "$UI_RESET" \
    "$(_github_prs_authored_cell "$age_w"    "$age_color"    "$age")" \
    "$(_github_prs_authored_cell "$rev_w"    "$rev_color"    "$rev_icon")" \
    "$(_github_prs_authored_cell "$counts_w" "$counts_color" "$approved/$total")" \
    "$(ui_paint "$title_color" "$title")"
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
