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
          status: {name: "In Progress", statusCategory: {key: "indeterminate"}},
          updated: $t1
        }
      },
      {
        key: "DEMO-87",
        fields: {
          summary: "Investigate stale cache on cold start",
          priority: {name: "High"},
          status: {name: "In Review", statusCategory: {key: "indeterminate"}},
          updated: $t2
        }
      },
      {
        key: "DEMO-64",
        fields: {
          summary: "Plan migration to bash 5.2",
          priority: {name: "Highest"},
          status: {name: "Backlog", statusCategory: {key: "new"}},
          updated: $t3
        }
      },
      {
        key: "DEMO-42",
        fields: {
          summary: "Document the components conventions",
          priority: {name: "None"},
          status: {name: "Open", statusCategory: {key: "new"}},
          updated: $t4
        }
      },
      {
        key: "DEMO-12",
        fields: {
          summary: "Audit color palette for contrast",
          priority: {name: "Low"},
          status: {name: "In Progress", statusCategory: {key: "indeterminate"}},
          updated: $t5
        }
      }
    ]'
}
