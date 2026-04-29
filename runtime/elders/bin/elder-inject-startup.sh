#!/usr/bin/env bash
# elder-inject-startup.sh <N>
#
# Inject the 3-command startup sequence into elder-N's tmux REPL:
#   /clear
#   /rename "Clan World: <Name>"
#   /color <color>
#
# Usage:
#   ~/clan-world/bin/elder-inject-startup.sh 1     # inject into elder-1 only
#   ~/clan-world/bin/elder-inject-startup.sh all   # inject into all 4
#
# Pauses 300ms between each command to let the CLI process them in order.
# Safe to re-run — /clear is idempotent, /rename + /color are stateless setters.
#
# Why a separate helper instead of running these inline in run.sh:
#   Slash commands like /clear, /rename, /color are processed by the Claude
#   Code CLI's input layer (typed-in commands), NOT by the model or by env
#   vars. They have to be physically typed into the REPL after it's running.
#   tmux send-keys with sleeps is the only reliable way.

set -euo pipefail

# Per-elder name + color mapping
declare -A NAMES=(
  [1]="Storm Riders"
  [2]="Iron Guard"
  [3]="Crimson"
  [4]="Verdant Wardens"
)
declare -A COLORS=(
  [1]="blue"
  [2]="cyan"
  [3]="red"
  [4]="green"
)

inject_one() {
  local n="$1"
  local name="${NAMES[$n]:-}"
  local color="${COLORS[$n]:-}"

  if [ -z "$name" ] || [ -z "$color" ]; then
    echo "elder-$n: not in mapping" >&2
    return 1
  fi

  if ! tmux has-session -t "elder-$n" 2>/dev/null; then
    echo "elder-$n: tmux session not running — skip" >&2
    return 1
  fi

  echo "elder-$n: injecting /clear + /rename \"Clan World: $name\" + /color $color"

  tmux send-keys -t "elder-$n" "/clear"; sleep 0.3
  tmux send-keys -t "elder-$n" Enter; sleep 0.3
  tmux send-keys -t "elder-$n" "/rename \"Clan World: $name\""; sleep 0.3
  tmux send-keys -t "elder-$n" Enter; sleep 0.3
  tmux send-keys -t "elder-$n" "/color $color"; sleep 0.3
  tmux send-keys -t "elder-$n" Enter
}

target="${1:-}"
if [ -z "$target" ]; then
  echo "usage: $0 <N>|all" >&2
  exit 2
fi

if [ "$target" = "all" ]; then
  for n in 1 2 3 4; do
    inject_one "$n" || true
  done
else
  inject_one "$target"
fi
