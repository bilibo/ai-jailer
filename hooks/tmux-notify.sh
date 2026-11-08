#!/usr/bin/env bash
# tmux-notify <waiting|clear>: colour the tmux window a Claude Code session
# runs in when it waits for input, and clear it on the next prompt. The
# Notification, Stop and UserPromptSubmit hooks call this. No tmux: no-op.
#
# Both window styles are set: tmux's default status-format draws the
# current window's tab with `window-status-current-style` alone whenever
# that option is not `default`, so a colour in `window-status-style` only
# shows once you switch to another window (RAU-37).
set -uo pipefail
PATH="@path@:${PATH:-}"
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
style="bg=colour214,fg=black"
case "${1:-}" in
  waiting)
    tmux set-window-option -t "$TMUX_PANE" window-status-style "$style" 2>/dev/null
    tmux set-window-option -t "$TMUX_PANE" window-status-current-style "$style" 2>/dev/null
    ;;
  clear)
    tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null
    tmux set-window-option -t "$TMUX_PANE" -u window-status-current-style 2>/dev/null
    ;;
esac
exit 0
