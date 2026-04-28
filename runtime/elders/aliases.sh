# ClanWorld Elders shell aliases — source from ~/.bashrc or ad-hoc:
#   source ~/clan-world/aliases.sh
#
# Provides:
#   elder-1 ... elder-4   attach to that Elder's tmux session
#   elders-up             start all 4 Elder sessions (Makefile-backed)
#   elders-down           kill all 4 Elder sessions
#   elders-status         list which Elder sessions are alive
#   elder-up <N>          start one Elder
#
# These aliases delegate to the Makefile at $_ELDER_DIR/Makefile
# so the actual logic stays in one place.

# Detect directory where this file lives (bash and zsh compatible)
if [ -n "${BASH_VERSION:-}" ]; then
  _ELDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _ELDER_DIR="${0:A:h}"
else
  _ELDER_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

elders-up()     { make -C "$_ELDER_DIR" --no-print-directory elders-up; }
elders-down()   { make -C "$_ELDER_DIR" --no-print-directory elders-down; }
elders-status() { make -C "$_ELDER_DIR" --no-print-directory elders-status; }

elder-up() {
  local n="$1"
  if [[ ! "$n" =~ ^[1-4]$ ]]; then
    echo "usage: elder-up <N>   where N is 1, 2, 3, or 4" >&2
    return 1
  fi
  make -C "$_ELDER_DIR" --no-print-directory "elder-$n"
}

# Quick attach shortcuts — auto-start the session if it's not running yet
alias elder-1='tmux has-session -t elder-1 2>/dev/null || elder-up 1; tmux attach -t elder-1'
alias elder-2='tmux has-session -t elder-2 2>/dev/null || elder-up 2; tmux attach -t elder-2'
alias elder-3='tmux has-session -t elder-3 2>/dev/null || elder-up 3; tmux attach -t elder-3'
alias elder-4='tmux has-session -t elder-4 2>/dev/null || elder-up 4; tmux attach -t elder-4'
