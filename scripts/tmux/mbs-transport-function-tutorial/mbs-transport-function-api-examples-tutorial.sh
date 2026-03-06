#!/bin/bash

SESSION="mbstf-tutorial"
OPEN5GS_BASE_DIR=~/5gmag/open5gs_mbs
MBSTF_BASE_DIR=/usr/local/bin
MEDIA_SERVER_BASE_DIR=~/5gmag/rt-mbs-examples/express-mock-media-server
PANE_PGIDS=()
PANE_PIDS=()

# PANE_PIDS stores the direct process ID of the command running in each tmux pane (the main service). PANE_PGIDS stores the process group ID for that pane, which lets you terminate any child processes spawned by the service (same process group).
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

kill_pane_targets() {
  local signal="$1"

  for pid in "${PANE_PIDS[@]}"; do
    kill "$signal" "$pid" 2>/dev/null || true
  done
  for pgid in "${PANE_PGIDS[@]}"; do
    kill "$signal" -- "-$pgid" 2>/dev/null || true
  done
}

cleanup() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    return
  fi

  # Terminate all process groups tied to panes from this session.
  kill_pane_targets -TERM
}

trap cleanup EXIT

# End existing session if it exists

tmux kill-session -t $SESSION 2>/dev/null

# New session with new windows

tmux new-session -d -s $SESSION -n "NRF" "$OPEN5GS_BASE_DIR/install/bin/open5gs-nrfd"
register_pane_pgid "$SESSION:NRF"

tmux new-window -t $SESSION -n "SCP" "$OPEN5GS_BASE_DIR/install/bin/open5gs-scpd"
register_pane_pgid "$SESSION:SCP"

tmux new-window -t $SESSION -n "SMF" "$OPEN5GS_BASE_DIR/install/bin/open5gs-smfd"
register_pane_pgid "$SESSION:SMF"

tmux new-window -t $SESSION -n "UPF" "sudo $OPEN5GS_BASE_DIR/install/bin/open5gs-upfd"
register_pane_pgid "$SESSION:UPF"

tmux new-window -t $SESSION -n "AMF" "$OPEN5GS_BASE_DIR/install/bin/open5gs-amfd"
register_pane_pgid "$SESSION:AMF"

tmux new-window -t $SESSION -n "MBSTF" "$MBSTF_BASE_DIR/open5gs-mbstfd"
register_pane_pgid "$SESSION:MBSTF"

tmux new-window -t $SESSION -n "MediaServer" "cd \"$MEDIA_SERVER_BASE_DIR\" && npm start"
register_pane_pgid "$SESSION:MediaServer"

# Connect session
tmux attach -t $SESSION

