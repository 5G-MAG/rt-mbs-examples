#!/bin/bash

SESSION="mbsf-tutorial"
BASE_DIR=~/5gmag/open5gs_mbs_development
PANE_PGIDS=()
PANE_PIDS=()

register_pane_pgid() {
  local pane_id="$1"
  local pane_pid
  local pgid

  # Get the PID of the pane's process
  pane_pid="$(tmux display-message -p -t "$pane_id" "#{pane_pid}")"

  # Get the process group ID
  pgid="$(ps -o pgid= -p "$pane_pid" | tr -d ' ')"

  if [[ -n "$pane_pid" ]]; then
    PANE_PIDS+=("$pane_pid")
  fi

  if [[ -n "$pgid" ]]; then
    PANE_PGIDS+=("$pgid")
  fi
}

cleanup() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    return
  fi

  # Terminate all process groups tied to panes from this session.
  for pid in "${PANE_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pgid in "${PANE_PGIDS[@]}"; do
    kill -TERM -- "-$pgid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${PANE_PIDS[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  for pgid in "${PANE_PGIDS[@]}"; do
    kill -KILL -- "-$pgid" 2>/dev/null || true
  done
}

trap cleanup EXIT

# End existing session if it exists

tmux kill-session -t $SESSION 2>/dev/null

# New session with new windows

tmux new-session -d -s $SESSION -n "NRF" "$BASE_DIR/install/bin/open5gs-nrfd"
register_pane_pgid "$SESSION:NRF"

tmux new-window -t $SESSION -n "SCP" "$BASE_DIR/install/bin/open5gs-scpd"
register_pane_pgid "$SESSION:SCP"

tmux new-window -t $SESSION -n "SMF" "$BASE_DIR/install/bin/open5gs-smfd"
register_pane_pgid "$SESSION:SMF"

tmux new-window -t $SESSION -n "UPF" "sudo $BASE_DIR/install/bin/open5gs-upfd"
register_pane_pgid "$SESSION:UPF"

tmux new-window -t $SESSION -n "AMF" "$BASE_DIR/install/bin/open5gs-amfd"
register_pane_pgid "$SESSION:AMF"

tmux new-window -t $SESSION -n "UDM" "$BASE_DIR/install/bin/open5gs-udmd"
register_pane_pgid "$SESSION:UDM"

tmux new-window -t $SESSION -n "MBSTF" "/usr/local/bin/open5gs-mbstfd"
register_pane_pgid "$SESSION:MBSTF"

tmux new-window -t $SESSION -n "MBSF" "/usr/local/bin/open5gs-mbsfd -c $BASE_DIR/local-mbsf.yaml"
register_pane_pgid "$SESSION:MBSF"

# Connect session

tmux attach -t $SESSION

