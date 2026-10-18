#!/usr/bin/env bash
# tmux-notify <waiting|clear>: colour the tmux window a Claude Code session
# runs in when it waits for input, and clear it on the next prompt. The
# Notification and UserPromptSubmit hooks (managed or repo settings) call
# this. No tmux: no-op.
set -uo pipefail
PATH="@path@:${PATH:-}"
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
case "${1:-}" in
  waiting) tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour214,fg=black" 2>/dev/null ;;
  clear)   tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null ;;
esac
exit 0
