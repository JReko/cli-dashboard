#!/usr/bin/env bash
# lib/ui.sh — terminal styling helpers (Catppuccin Mocha 24-bit palette, Nerd
# Font icons w/ ASCII fallback, OSC 8 hyperlinks). Honors NO_COLOR
# (https://no-color.org/) and UI_NO_NERDFONT=1.

# All UI_* vars are consumed by sourcing scripts; shellcheck can't see that.
# shellcheck disable=SC2034

# --- Palette (Catppuccin Mocha) -----------------------------------------------
UI_RESET=$'\e[0m'
UI_BOLD=$'\e[1m'
UI_DIM=$'\e[2m'

UI_TEXT=$'\e[38;2;205;214;244m'      # base text
UI_MUTED=$'\e[38;2;108;112;134m'     # overlay0 — muted/dim text
UI_SUBTLE=$'\e[38;2;186;194;222m'    # subtext1
UI_OK=$'\e[38;2;166;227;161m'        # green
UI_KO=$'\e[38;2;243;139;168m'        # red
UI_WARN=$'\e[38;2;249;226;175m'      # yellow
UI_INFO=$'\e[38;2;137;220;235m'      # sky
UI_ACCENT=$'\e[38;2;203;166;247m'    # mauve
UI_LINK=$'\e[38;2;180;190;254m'      # lavender — URL-like

# --- Icons (Nerd Font; fallback to ASCII when UI_NO_NERDFONT=1) ---------------
if [[ -n "${UI_NO_NERDFONT:-}" ]]; then
  UI_ICON_GITHUB='[gh]'
  UI_ICON_PR='PR'
  UI_ICON_OK='OK'
  UI_ICON_KO='KO'
  UI_ICON_WARN='!!'
  UI_ICON_PENDING='..'
  UI_ICON_USER='@'
  UI_ICON_REPO='R'
  UI_ICON_CLOCK='t'
  UI_ICON_MERGE='M'
  UI_ICON_BREW='[brew]'
  UI_ICON_PACKAGE='pkg'
  UI_ICON_CASK='cask'
  UI_ICON_ARROW='->'
  UI_ICON_JIRA='[jira]'
  UI_ICON_TICKET='#'
else
  UI_ICON_GITHUB=$''           # nf-fa-github
  UI_ICON_PR=$''               # nf-oct-git_pull_request
  UI_ICON_OK=$''               # nf-fa-check
  UI_ICON_KO=$''               # nf-fa-times
  UI_ICON_WARN=$''             # nf-fa-exclamation_triangle
  UI_ICON_PENDING=$''          # nf-fa-hourglass_half
  UI_ICON_USER=$''             # nf-fa-user
  UI_ICON_REPO=$''             # nf-oct-repo
  UI_ICON_CLOCK=$''            # nf-fa-clock_o
  UI_ICON_MERGE=$''            # nf-dev-git_merge
  UI_ICON_BREW=$''             # nf-fa-beer
  UI_ICON_PACKAGE=$''          # nf-oct-package
  UI_ICON_CASK=$''             # nf-fa-cube
  UI_ICON_ARROW=$''            # nf-fa-long_arrow_right
  UI_ICON_JIRA=$'\xef\x82\xae'             # nf-fa-tasks
  UI_ICON_TICKET=$'\xef\x85\x85'           # nf-fa-ticket
fi

# --- NO_COLOR -----------------------------------------------------------------
if [[ -n "${NO_COLOR:-}" ]]; then
  UI_RESET='' UI_BOLD='' UI_DIM=''
  UI_TEXT='' UI_MUTED='' UI_SUBTLE=''
  UI_OK='' UI_KO='' UI_WARN='' UI_INFO='' UI_ACCENT='' UI_LINK=''
fi

# --- Helpers ------------------------------------------------------------------

# ui_paint <color> <text...> — wrap text in color + reset.
ui_paint() {
  local color="$1"; shift
  printf '%s%s%s' "$color" "$*" "$UI_RESET"
}

# ui_section_header <icon> <title> — bold accent header with a thin underline
# the same visible width as "icon + space + title".
ui_section_header() {
  local icon="$1" title="$2" line='' i width
  width=$(( ${#icon} + 1 + ${#title} ))
  for (( i=0; i<width; i++ )); do line+='─'; done
  printf '\n%s%s%s %s%s\n' "$UI_BOLD" "$UI_ACCENT" "$icon" "$title" "$UI_RESET"
  printf '%s%s%s\n' "$UI_MUTED" "$line" "$UI_RESET"
}

# ui_hyperlink <url> <text> — OSC 8 clickable link (iTerm2/Terminal.app/wezterm).
ui_hyperlink() {
  local url="$1" text="$2"
  # shellcheck disable=SC1003  # `\e\\` is OSC 8 ST (ESC + backslash), not an escape error.
  printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$url" "$text"
}
