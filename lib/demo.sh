#!/usr/bin/env bash
# lib/demo.sh — fake payloads for DASHBOARD_DEMO=true. Each function returns
# the same JSON shape the real CLI would, so component rendering is unchanged.

# Give Jira a placeholder host so OSC 8 hyperlinks still render.
if config_enabled DASHBOARD_DEMO 2>/dev/null; then
  : "${JIRA_HOST:=https://demo.atlassian.net}"
fi

# ISO 8601 UTC timestamp for "$1 ago" (e.g. "3 hours", "2 days").
_demo_ago() { gdate -u -d "$1 ago" +%Y-%m-%dT%H:%M:%SZ; }

demo_brew_outdated_formulae_payload() {
  cat <<'JSON'
{
  "formulae": [
    {"name": "jq", "installed_versions": ["1.7"], "current_version": "1.7.1"},
    {"name": "node", "installed_versions": ["20.11.0"], "current_version": "21.6.1"},
    {"name": "ripgrep", "installed_versions": ["14.1.0"], "current_version": "14.1.1"},
    {"name": "tree", "installed_versions": ["2.1.0"], "current_version": "2.1.1"}
  ],
  "casks": []
}
JSON
}

demo_brew_outdated_casks_payload() {
  cat <<'JSON'
{
  "formulae": [],
  "casks": [
    {"name": "iterm2", "installed_versions": "3.4.23", "current_version": "3.5.0"},
    {"name": "visual-studio-code", "installed_versions": "1.85.0", "current_version": "1.86.2"}
  ]
}
JSON
}

demo_github_api_login() { printf 'octocat'; }

demo_version_update_check_payload() {
  cat <<'JSON'
{
  "tag_name": "v1.0.2",
  "name": "v1.0.2",
  "html_url": "https://github.com/JReko/cli-dashboard/releases/tag/v1.0.2"
}
JSON
}

demo_github_prs_review_requested_payload() {
  jq -n \
    --arg t1 "$(_demo_ago '2 hours')" \
    --arg t2 "$(_demo_ago '4 hours')" \
    --arg t3 "$(_demo_ago '1 day')" \
    --arg t4 "$(_demo_ago '3 days')" \
    '{
      data: {
        search: {
          nodes: [
            {
              number: 42,
              title: "Bump jq 1.7 -> 1.7.1",
              url: "https://github.com/octocat/hello-world/pull/42",
              createdAt: $t1,
              author: {login: "octocat"},
              repository: {nameWithOwner: "octocat/hello-world"},
              mergeable: "MERGEABLE",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "SUCCESS"}}}]}
            },
            {
              number: 87,
              title: "Add CI workflow for shellcheck",
              url: "https://github.com/octocat/spoon-knife/pull/87",
              createdAt: $t2,
              author: {login: "hubot"},
              repository: {nameWithOwner: "octocat/spoon-knife"},
              mergeable: "MERGEABLE",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "PENDING"}}}]}
            },
            {
              number: 155,
              title: "Refactor render pipeline",
              url: "https://github.com/octocat/hello-world/pull/155",
              createdAt: $t3,
              author: {login: "monalisa"},
              repository: {nameWithOwner: "octocat/hello-world"},
              mergeable: "CONFLICTING",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "SUCCESS"}}}]}
            },
            {
              number: 12,
              title: "Fix flaky test in date parsing",
              url: "https://github.com/acme/widget/pull/12",
              createdAt: $t4,
              author: {login: "octocat"},
              repository: {nameWithOwner: "acme/widget"},
              mergeable: "MERGEABLE",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "FAILURE"}}}]}
            }
          ]
        }
      }
    }'
}

demo_github_prs_authored_payload() {
  jq -n \
    --arg t1 "$(_demo_ago '30 minutes')" \
    --arg t2 "$(_demo_ago '5 hours')" \
    --arg t3 "$(_demo_ago '2 days')" \
    --arg t4 "$(_demo_ago '6 days')" \
    '{
      data: {
        search: {
          nodes: [
            {
              number: 314,
              title: "Add prs_authored feature to github component",
              url: "https://github.com/octocat/hello-world/pull/314",
              createdAt: $t1,
              isDraft: false,
              repository: {nameWithOwner: "octocat/hello-world"},
              mergeable: "MERGEABLE",
              reviewDecision: "APPROVED",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "SUCCESS"}}}]},
              latestReviews: {nodes: [{state: "APPROVED"}, {state: "APPROVED"}]},
              reviewRequests: {totalCount: 0}
            },
            {
              number: 271,
              title: "Wire up retry logic for flaky API calls",
              url: "https://github.com/acme/widget/pull/271",
              createdAt: $t2,
              isDraft: false,
              repository: {nameWithOwner: "acme/widget"},
              mergeable: "MERGEABLE",
              reviewDecision: "CHANGES_REQUESTED",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "FAILURE"}}}]},
              latestReviews: {nodes: [{state: "CHANGES_REQUESTED"}]},
              reviewRequests: {totalCount: 1}
            },
            {
              number: 199,
              title: "Switch demo timestamps to ISO 8601",
              url: "https://github.com/octocat/spoon-knife/pull/199",
              createdAt: $t3,
              isDraft: false,
              repository: {nameWithOwner: "octocat/spoon-knife"},
              mergeable: "CONFLICTING",
              reviewDecision: "REVIEW_REQUIRED",
              commits: {nodes: [{commit: {statusCheckRollup: {state: "PENDING"}}}]},
              latestReviews: {nodes: [{state: "APPROVED"}, {state: "COMMENTED"}]},
              reviewRequests: {totalCount: 1}
            },
            {
              number: 42,
              title: "Bump base image to the latest LTS",
              url: "https://github.com/acme/gadget/pull/42",
              createdAt: $t3,
              isDraft: false,
              repository: {nameWithOwner: "acme/gadget"},
              mergeable: "MERGEABLE",
              reviewDecision: null,
              commits: {nodes: [{commit: {statusCheckRollup: {state: "SUCCESS"}}}]},
              latestReviews: {nodes: []},
              reviewRequests: {totalCount: 1}
            },
            {
              number: 88,
              title: "WIP: extract shared age helper",
              url: "https://github.com/octocat/hello-world/pull/88",
              createdAt: $t4,
              isDraft: true,
              repository: {nameWithOwner: "octocat/hello-world"},
              mergeable: "MERGEABLE",
              reviewDecision: null,
              commits: {nodes: [{commit: {statusCheckRollup: {state: "NONE"}}}]},
              latestReviews: {nodes: []},
              reviewRequests: {totalCount: 0}
            }
          ]
        }
      }
    }'
}

demo_jira_assigned_issues_payload() {
  jq -n \
    --arg t1 "$(_demo_ago '3 hours')" \
    --arg t2 "$(_demo_ago '1 day')" \
    --arg t3 "$(_demo_ago '2 days')" \
    --arg t4 "$(_demo_ago '5 days')" \
    --arg t5 "$(_demo_ago '12 days')" \
    '[
      {
        key: "DEMO-101",
        fields: {
          summary: "Wire up dashboard demo mode",
          priority: {name: "Medium"},
          status: {name: "In Progress"},
          updated: $t1
        }
      },
      {
        key: "DEMO-87",
        fields: {
          summary: "Investigate stale cache on cold start",
          priority: {name: "High"},
          status: {name: "In Review"},
          updated: $t2
        }
      },
      {
        key: "DEMO-64",
        fields: {
          summary: "Plan migration to bash 5.2",
          priority: {name: "Highest"},
          status: {name: "Backlog"},
          updated: $t3
        }
      },
      {
        key: "DEMO-42",
        fields: {
          summary: "Document the components conventions",
          priority: {name: "None"},
          status: {name: "Open"},
          updated: $t4
        }
      },
      {
        key: "DEMO-12",
        fields: {
          summary: "Audit color palette for contrast",
          priority: {name: "Low"},
          status: {name: "In Progress"},
          updated: $t5
        }
      }
    ]'
}

# Keys of the mock issues in an "In Progress" status category, one per line —
# what `jira issue list --plain --no-headers --columns key` prints.
demo_jira_in_progress_keys_payload() {
  printf '%s\n' DEMO-101 DEMO-87 DEMO-12
}

# Review queue history, "YYYY-MM-DD count" per day, ending today. Same shape as
# PULSE_HISTORY_FILE.
demo_pulse_trend_payload() {
  local -a series=(2 3 3 5 6 4 3 5 7 6 4 3 5 4)
  local i n=${#series[@]}
  for i in "${!series[@]}"; do
    printf '%s %s\n' "$(gdate -d "-$(( n - 1 - i )) days" +%F)" "${series[i]}"
  done
}
