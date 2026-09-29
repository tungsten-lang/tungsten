#!/bin/zsh
# Run a short command with my own search tree paused (SIGSTOP) so at most 2 rollout workers run at once; always resume (SIGCONT).
#   scratchpad/bat/paused.sh ROOT_PID -- command args...
root=$1; shift; shift
desc() { for p in $(pgrep -P $1); do echo $p; desc $p; done; }
PIDS="$root $(desc $root | tr '\n' ' ')"
for p in ${=PIDS}; do kill -STOP $p 2>/dev/null; done
trap 'for p in ${=PIDS}; do kill -CONT $p 2>/dev/null; done' EXIT INT TERM
"$@"
