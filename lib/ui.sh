#!/usr/bin/env bash
# lib/ui.sh — terminal styling helpers (Catppuccin Mocha 24-bit palette, Nerd
# Font icons w/ ASCII fallback, OSC 8 hyperlinks). Honors NO_COLOR
# (https://no-color.org/) and UI_NO_NERDFONT=1.

# All UI_* vars are consumed by sourcing scripts; shellcheck can't see that.
# shellcheck disable=SC2034

# ui_strip matches escape sequences with extended globs.
shopt -s extglob

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
  UI_ICON_REVIEW='RV'
  UI_ICON_USER='@'
  UI_ICON_REPO='R'
  UI_ICON_CLOCK='t'
  UI_ICON_BREW='[brew]'
  UI_ICON_PACKAGE='pkg'
  UI_ICON_CASK='cask'
  UI_ICON_ARROW='->'
  UI_ICON_JIRA='[jira]'
  UI_ICON_TICKET='#'
  UI_ICON_PULSE='~'
  UI_SPINNER=('|' '/' '-' $'\\')
  UI_ICON_PRIO_HIGHEST='^^'
  UI_ICON_PRIO_HIGH='^'
  UI_ICON_PRIO_MEDIUM='='
  UI_ICON_PRIO_LOW='v'
  UI_BAR_ON='='
  UI_BAR_OFF='-'
  UI_BOX_ON='x'
  UI_BOX_OFF='o'
  UI_SPARK=(' ' '.' ',' '-' '~' '=' '*' '#')
else
  UI_ICON_GITHUB=$''           # nf-fa-github
  UI_ICON_PR=$''               # nf-oct-git_pull_request
  UI_ICON_OK=$''               # nf-fa-check
  UI_ICON_KO=$''               # nf-fa-times
  UI_ICON_WARN=$''             # nf-fa-exclamation_triangle
  UI_ICON_REVIEW=$'\xef\x81\xae' # nf-fa-eye
  UI_ICON_USER=$''             # nf-fa-user
  UI_ICON_REPO=$''             # nf-oct-repo
  UI_ICON_CLOCK=$''            # nf-fa-clock_o
  UI_ICON_BREW=$''             # nf-fa-beer
  UI_ICON_PACKAGE=$''          # nf-oct-package
  UI_ICON_CASK=$''             # nf-fa-cube
  UI_ICON_ARROW=$''            # nf-fa-long_arrow_right
  UI_ICON_JIRA=$'\xef\x82\xae'             # nf-fa-tasks
  UI_ICON_TICKET=$'\xef\x85\x85'           # nf-fa-ticket
  UI_ICON_PULSE=$'\xef\x88\x9e'            # nf-fa-heartbeat
  UI_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)  # braille dots
  UI_ICON_PRIO_HIGHEST='⇈'
  UI_ICON_PRIO_HIGH='↑'
  UI_ICON_PRIO_MEDIUM='='
  UI_ICON_PRIO_LOW='↓'
  UI_BAR_ON='━'
  UI_BAR_OFF='─'
  UI_BOX_ON='■'
  UI_BOX_OFF='□'
  UI_SPARK=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
fi

# --- NO_COLOR -----------------------------------------------------------------
if [[ -n "${NO_COLOR:-}" ]]; then
  UI_RESET='' UI_BOLD='' UI_DIM=''
  UI_TEXT='' UI_MUTED='' UI_SUBTLE=''
  UI_OK='' UI_KO='' UI_WARN='' UI_INFO='' UI_ACCENT='' UI_LINK=''
fi

# --- Screen control ----------------------------------------------------------
# Raw ANSI, not tput: no extra dependency, and the file already speaks escapes.
# All no-ops off a TTY so piped output stays clean.

ui_cursor_hide() { if [[ -t 1 ]]; then printf '\e[?25l'; fi; }
ui_cursor_show() { if [[ -t 1 ]]; then printf '\e[?25h'; fi; }

# Home the cursor and erase everything below it. Preferred over `clear`, which
# also drops the scrollback and flashes between frames.
ui_screen_reset() { if [[ -t 1 ]]; then printf '\e[H\e[J'; fi; }

ui_cursor_home()  { if [[ -t 1 ]]; then printf '\e[H'; fi; }
ui_line_erase()   { if [[ -t 1 ]]; then printf '\e[2K\r'; fi; }

# --- Basics -------------------------------------------------------------------

# Width hint for whatever is being rendered: content width of the panel the
# current component lands in. The dashboard sets it per worker.
UI_WIDTH="${UI_WIDTH:-80}"

# Marker for out-of-band lines a component sends to its panel frame (title,
# badge) instead of the body. ASCII record separator: never in real output.
UI_PANEL_MARK=$'\x1e'

# Prefix ui_table puts on data rows: the dashboard may drop rows from the end of
# such a run to fit the terminal height, replacing them with "+N more".
UI_ROW_MARK="${UI_PANEL_MARK}R"
# Prefix on a table's column-header row: dropped along with every row under it.
UI_HEAD_MARK="${UI_PANEL_MARK}H"

# Cell separator for ui_table / ui_inline_list: "<color>\x1f<text>[\x1f<url>]".
UI_CELL=$'\x1f'

# ui_paint <color> <text...> — wrap text in color + reset.
ui_paint() {
  local color="$1"; shift
  printf '%s%s%s' "$color" "$*" "$UI_RESET"
}

# ui_hyperlink <url> <text> — OSC 8 clickable link (iTerm2/Terminal.app/wezterm).
ui_hyperlink() {
  local url="$1" text="$2"
  # shellcheck disable=SC1003  # `\e\\` is OSC 8 ST (ESC + backslash), not an escape error.
  printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$url" "$text"
}

# ui_cell <color> <text> [url] — one ui_table / ui_inline_list cell.
ui_cell() {
  printf '%s%s%s' "$1" "$UI_CELL" "$2"
  if [[ -n ${3:-} ]]; then printf '%s%s' "$UI_CELL" "$3"; fi
}

# ui_strip <text> — sets UI_REPLY to text minus SGR colors and OSC 8 links, i.e.
# what the terminal actually shows. Pure bash: called per line, per frame.
ui_strip() {
  local s="$1"
  s=${s//$'\e['*([0-9;])m/}
  s=${s//$'\e]8;;'*([!$'\e'])$'\e\\'/}
  UI_REPLY="$s"
}

# ui_truncate <text> <width> — sets UI_REPLY to plain text cut to width with "…".
ui_truncate() {
  local text="$1" width="$2"
  if (( width <= 0 )); then UI_REPLY=''; return; fi
  if (( ${#text} > width )); then text="${text:0:width-1}…"; fi
  UI_REPLY="$text"
}

# ui_repeat <char> <count> — sets UI_REPLY to char repeated count times.
ui_repeat() {
  local out='' i
  for (( i = 0; i < $2; i++ )); do out+="$1"; done
  UI_REPLY="$out"
}

# --- Time ---------------------------------------------------------------------

# ui_age <iso8601> — sets UI_AGE_SECS and UI_AGE_LABEL ("30m", "5h", "2d").
# Unparseable timestamps give secs=0, label "?".
ui_age() {
  local started now diff
  UI_AGE_SECS=0
  UI_AGE_LABEL='?'
  if ! started=$(gdate -d "$1" +%s 2>/dev/null); then return 0; fi
  now=$(date +%s)
  UI_AGE_SECS=$(( now - started ))
  ui_age_label "$UI_AGE_SECS"
  UI_AGE_LABEL="$UI_REPLY"
}

# ui_age_label <secs> — sets UI_REPLY to "30m", "5h", "2d".
ui_age_label() {
  local diff="$1"
  if   (( diff < 3600 ));  then UI_REPLY="$(( diff / 60 ))m"
  elif (( diff < 86400 )); then UI_REPLY="$(( diff / 3600 ))h"
  else                          UI_REPLY="$(( diff / 86400 ))d"
  fi
}

# ui_age_color <secs> <warn_after_secs> <ko_after_secs> — sets UI_REPLY to the
# staleness color: muted while fresh, then warn, then ko.
ui_age_color() {
  local secs="$1" warn="$2" ko="$3"
  if   (( secs >= ko ));   then UI_REPLY="$UI_KO"
  elif (( secs >= warn )); then UI_REPLY="$UI_WARN"
  else                          UI_REPLY="$UI_MUTED"
  fi
}

UI_HOUR=3600
UI_DAY=86400

# --- Panel protocol (component side) -----------------------------------------
# Components render body lines to stdout. These helpers emit marker lines the
# dashboard lifts into the panel frame instead.

# ui_panel_title <icon> <title> — the panel's top-left label.
ui_panel_title() {
  printf '%sT%s %s\n' "$UI_PANEL_MARK" "$1" "$2"
}

# ui_panel_badge <text> — appended to the panel's top-right label.
ui_panel_badge() {
  printf '%sB%s\n' "$UI_PANEL_MARK" "$1"
}

# ui_metric <key> <value> — publish a number for the pulse strip. Never shown
# in the component's own panel.
ui_metric() {
  printf '%sM%s=%s\n' "$UI_PANEL_MARK" "$1" "$2"
}

# --- Meters -------------------------------------------------------------------
# btop-style: bar cells are colored by their position along the bar, green →
# yellow → red, so a fuller bar literally runs hotter.

UI_GRADIENT_STOPS=(
  "166 227 161"
  "249 226 175"
  "243 139 168"
)

# ui_gradient <pos> <span> — sets UI_REPLY to the SGR color for cell pos of a
# span-cell bar.
ui_gradient() {
  local pos="$1" span="$2" t f r g b
  local -a from to
  if [[ -n ${NO_COLOR:-} ]]; then UI_REPLY=''; return; fi
  t=0
  if (( span > 1 )); then t=$(( pos * 1000 / (span - 1) )); fi
  if (( t < 500 )); then
    read -ra from <<<"${UI_GRADIENT_STOPS[0]}"
    read -ra to <<<"${UI_GRADIENT_STOPS[1]}"
    f=$(( t * 2 ))
  else
    read -ra from <<<"${UI_GRADIENT_STOPS[1]}"
    read -ra to <<<"${UI_GRADIENT_STOPS[2]}"
    f=$(( (t - 500) * 2 ))
  fi
  r=$(( from[0] + (to[0] - from[0]) * f / 1000 ))
  g=$(( from[1] + (to[1] - from[1]) * f / 1000 ))
  b=$(( from[2] + (to[2] - from[2]) * f / 1000 ))
  UI_REPLY=$'\e'"[38;2;${r};${g};${b}m"
}

# ui_bar <filled> <cells> [on] [off] — sets UI_REPLY to a painted bar: filled
# cells in gradient, the rest muted. Filled is clamped to [0, cells].
ui_bar() {
  local filled="$1" cells="$2" on="${3:-$UI_BAR_ON}" off="${4:-$UI_BAR_OFF}" out='' i
  if (( filled > cells )); then filled=$cells; fi
  if (( filled < 0 )); then filled=0; fi
  for (( i = 0; i < filled; i++ )); do
    ui_gradient "$i" "$cells"
    out+="$UI_REPLY$on"
  done
  if (( filled < cells )); then
    out+="$UI_MUTED"
    for (( i = filled; i < cells; i++ )); do out+="$off"; done
  fi
  UI_REPLY="$out$UI_RESET"
}

# ui_sparkline <rows> <value>... — prints rows lines of block characters, one
# column per value, scaled to the max. The last value is highlighted.
ui_sparkline() {
  local rows="$1"; shift
  local -a values=("$@")
  local levels=$(( rows * 8 )) max=1 v row i lvl cell line color
  for v in "${values[@]}"; do if (( v > max )); then max=$v; fi; done
  for (( row = rows - 1; row >= 0; row-- )); do
    line=''
    for i in "${!values[@]}"; do
      v=${values[i]}
      lvl=$(( v * levels / max ))
      if (( v > 0 && lvl == 0 )); then lvl=1; fi
      lvl=$(( lvl - row * 8 ))
      color="$UI_INFO"
      if (( i == ${#values[@]} - 1 )); then color="$UI_BOLD$UI_ACCENT"; fi
      if (( lvl <= 0 )); then
        if (( row == 0 )); then cell="$UI_MUTED${UI_SPARK[0]}"; else cell=' '; fi
      elif (( lvl >= 8 )); then
        cell="$color${UI_SPARK[7]}"
      else
        cell="$color${UI_SPARK[lvl - 1]}"
      fi
      line+="$cell$UI_RESET "
    done
    printf '%s\n' "${line% }"
  done
}

# --- Feature headers ----------------------------------------------------------

# ui_feature_header <icon> <title> <count> — "<icon> Title  N". An empty
# feature collapses to one muted "Title · none" line; callers skip the body.
ui_feature_header() {
  local icon="$1" title="$2" count="$3"
  if (( count == 0 )); then
    printf '%s%s %s %s·%s none%s\n' \
      "$UI_MUTED" "$icon" "$title" "$UI_MUTED" "$UI_MUTED" "$UI_RESET"
    return 0
  fi
  printf '%s%s%s %s%s%s%s  %s%s%s%s\n' \
    "$UI_ACCENT" "$icon" "$UI_RESET" \
    "$UI_BOLD" "$UI_TEXT" "$title" "$UI_RESET" \
    "$UI_BOLD" "$UI_ACCENT" "$count" "$UI_RESET"
}

# ui_feature_error <title> — the one-line failure state, pointing at the log.
ui_feature_error() {
  printf '%s%s%s %s%s%s %s·%s %s%s%s\n' \
    "$UI_KO" "$UI_ICON_KO" "$UI_RESET" \
    "$UI_BOLD" "$1" "$UI_RESET" \
    "$UI_MUTED" "$UI_RESET" \
    "$UI_KO" "ERROR (see $(log_path_display))" "$UI_RESET"
}

# --- Table --------------------------------------------------------------------

# Narrowest a :shrink column gets before the flex column starts losing width.
UI_TABLE_SHRINK_MIN=14

# ui_table <indent> <width> <col_spec>... — render rows read from stdin.
#
#   col_spec  "<header>[:r][:flex][:shrink]" — r right-aligns; exactly one flex
#             column absorbs leftover width and is truncated with "…" to fit.
#             When the flex column can't show its widest value, shrink columns
#             give up width first (left to right, down to UI_TABLE_SHRINK_MIN).
#   row       one line, cells tab-separated, each built with ui_cell.
#
# Columns size to their widest value (header included); the header row is
# muted and skipped when every header is empty. Links wrap the text only, never
# the padding. Rows carry UI_ROW_MARK (header: UI_HEAD_MARK) so the dashboard
# can trim them to fit the terminal height.
ui_table() {
  local indent="$1" width="$2"; shift 2
  local heads=() rights=() widths=() shrinks=() flex=-1 spec n=0 has_head=false

  for spec in "$@"; do
    heads+=("${spec%%:*}")
    rights+=(false)
    if [[ $spec == *:r* ]]; then rights[n]=true; fi
    if [[ $spec == *:flex* ]]; then flex=$n; fi
    if [[ $spec == *:shrink* ]]; then shrinks+=("$n"); fi
    widths+=("${#heads[n]}")
    if [[ -n ${heads[n]} ]]; then has_head=true; fi
    n=$(( n + 1 ))
  done

  local colors=() texts=() urls=() line cells cell rest text c r=0
  while IFS= read -r line; do
    IFS=$'\t' read -ra cells <<<"$line"
    for (( c = 0; c < n; c++ )); do
      cell="${cells[c]:-}"
      colors+=("${cell%%"$UI_CELL"*}")
      rest="${cell#*"$UI_CELL"}"
      text="${rest%%"$UI_CELL"*}"
      texts+=("$text")
      if [[ $rest == *"$UI_CELL"* ]]; then urls+=("${rest#*"$UI_CELL"}"); else urls+=(''); fi
      _ui_visible_len "$text"
      if (( UI_REPLY > widths[c] )); then widths[c]=$UI_REPLY; fi
    done
    r=$(( r + 1 ))
  done

  # Fit the flex column into what the fixed columns leave over.
  if (( flex >= 0 )); then
    local used=$(( indent + 2 * (n - 1) )) avail
    for (( c = 0; c < n; c++ )); do
      if (( c != flex )); then used=$(( used + widths[c] )); fi
    done
    avail=$(( width - used ))
    local floor give
    for c in ${shrinks[@]+"${shrinks[@]}"}; do
      if (( avail >= widths[flex] )); then break; fi
      floor=$UI_TABLE_SHRINK_MIN
      if (( ${#heads[c]} > floor )); then floor=${#heads[c]}; fi
      give=$(( widths[c] - floor ))
      if (( give > widths[flex] - avail )); then give=$(( widths[flex] - avail )); fi
      if (( give > 0 )); then
        widths[c]=$(( widths[c] - give ))
        avail=$(( avail + give ))
      fi
    done
    if (( avail < 8 )); then avail=8; fi
    if (( widths[flex] > avail )); then widths[flex]=$avail; fi
  fi

  local pad_indent out i row
  printf -v pad_indent '%*s' "$indent" ''

  if [[ $has_head == true ]]; then
    out="$UI_HEAD_MARK$pad_indent$UI_MUTED"
    for (( c = 0; c < n; c++ )); do
      _ui_table_fit "${heads[c]}" "${widths[c]}" "${rights[c]}" $(( c == n - 1 ))
      out+="$UI_REPLY"
      if (( c < n - 1 )); then out+='  '; fi
    done
    printf '%s%s\n' "${out%"${out##*[! ]}"}" "$UI_RESET"
  fi

  for (( row = 0; row < r; row++ )); do
    out="$UI_ROW_MARK$pad_indent"
    for (( c = 0; c < n; c++ )); do
      i=$(( row * n + c ))
      _ui_table_cell "${colors[i]}" "${texts[i]}" "${urls[i]}" \
        "${widths[c]}" "${rights[c]}" $(( c == n - 1 ))
      out+="$UI_REPLY"
      if (( c < n - 1 )); then out+='  '; fi
    done
    printf '%s\n' "$out"
  done
}

# _ui_visible_len <text> — UI_REPLY: on-screen width of text.
_ui_visible_len() {
  if [[ $1 == *$'\e'* ]]; then
    ui_strip "$1"
    UI_REPLY=${#UI_REPLY}
  else
    UI_REPLY=${#1}
  fi
}

# _ui_table_fit <text> <width> <right> <is_last> — truncate + pad plain text.
_ui_table_fit() {
  local text="$1" width="$2" right="$3" last="$4" pad=''
  ui_truncate "$text" "$width"
  text="$UI_REPLY"
  if (( width > ${#text} )) && ! [[ $last == 1 && $right == false ]]; then
    printf -v pad '%*s' $(( width - ${#text} )) ''
  fi
  if [[ $right == true ]]; then UI_REPLY="$pad$text"; else UI_REPLY="$text$pad"; fi
}

# Text that already carries escapes (bars, pips) is never cut: it is sized by
# its visible width instead.
_ui_table_cell() {
  local color="$1" text="$2" url="$3" width="$4" right="$5" last="$6" pad='' body len
  if [[ $text == *$'\e'* ]]; then
    _ui_visible_len "$text"
    len=$UI_REPLY
  else
    ui_truncate "$text" "$width"
    text="$UI_REPLY"
    len=${#text}
  fi
  if (( width > len )) && ! [[ $last == 1 && $right == false ]]; then
    printf -v pad '%*s' $(( width - len )) ''
  fi
  body="$color$text$UI_RESET"
  if [[ -n $url ]]; then body=$(ui_hyperlink "$url" "$body"); fi
  if [[ $right == true ]]; then UI_REPLY="$pad$body"; else UI_REPLY="$body$pad"; fi
}

# ui_inline_list <width> <cell>... — cells joined with " · " on one line,
# cut with "+N" when they don't fit width. Sets UI_REPLY.
ui_inline_list() {
  local width="$1"; shift
  local total=$# shown=0 used=0 out='' cell color text sep_len more
  local sep=" $UI_MUTED·$UI_RESET "
  for cell in "$@"; do
    color="${cell%%"$UI_CELL"*}"
    text="${cell#*"$UI_CELL"}"
    text="${text%%"$UI_CELL"*}"
    sep_len=0
    if (( shown > 0 )); then sep_len=3; fi
    more="+$(( total - shown - 1 ))"
    # Reserve room for a trailing "+N" unless this is the last item.
    if (( shown + 1 < total )); then
      if (( used + sep_len + ${#text} + 3 + ${#more} > width )); then break; fi
    elif (( used + sep_len + ${#text} > width )); then
      break
    fi
    if (( shown > 0 )); then out+="$sep"; fi
    out+="$color$text$UI_RESET"
    used=$(( used + sep_len + ${#text} ))
    shown=$(( shown + 1 ))
  done
  if (( shown < total )); then
    out+="$sep$UI_MUTED+$(( total - shown ))$UI_RESET"
  fi
  UI_REPLY="$out"
}

# --- Panels (dashboard side) --------------------------------------------------

# ui_panel <width> <height> <title> <badge> [line...] — print a rounded box,
# width columns wide, at least height rows tall, around the body lines. Lines
# wider than the box are flattened to plain text and cut, so a misbehaving
# component can't break the frame.
ui_panel() {
  local width="$1" height="$2" title="$3" badge="$4"; shift 4
  local inner=$(( width - 4 )) line pad fill title_len badge_len
  local b="$UI_MUTED" t="$UI_BOLD$UI_ACCENT"

  ui_strip "$title"; title_len=${#UI_REPLY}
  ui_strip "$badge"; badge_len=${#UI_REPLY}
  fill=$(( width - 6 - title_len ))
  if (( badge_len > 0 )); then fill=$(( fill - badge_len - 3 )); fi
  if (( fill < 1 )); then badge=''; fill=$(( width - 6 - title_len )); fi
  ui_repeat '─' "$fill"
  if [[ -n $badge ]]; then
    printf '%s╭─ %s%s%s %s%s─ %s%s %s─╮%s\n' \
      "$b" "$t" "$title" "$UI_RESET" "$b" "$UI_REPLY" "$badge" "$UI_RESET" "$b" "$UI_RESET"
  else
    printf '%s╭─ %s%s%s %s%s─╮%s\n' "$b" "$t" "$title" "$UI_RESET" "$b" "$UI_REPLY" "$UI_RESET"
  fi

  local body=("$@")
  while (( ${#body[@]} < height - 2 )); do body+=(''); done
  for line in "${body[@]}"; do
    ui_strip "$line"
    if (( ${#UI_REPLY} > inner )); then
      ui_truncate "$UI_REPLY" "$inner"
      line="$UI_TEXT$UI_REPLY"
    fi
    printf -v pad '%*s' $(( inner - ${#UI_REPLY} )) ''
    printf '%s│%s %s%s%s %s│%s\n' "$b" "$UI_RESET" "$line" "$UI_RESET" "$pad" "$b" "$UI_RESET"
  done

  ui_repeat '─' $(( width - 2 ))
  printf '%s╰%s╯%s\n' "$b" "$UI_REPLY" "$UI_RESET"
}
