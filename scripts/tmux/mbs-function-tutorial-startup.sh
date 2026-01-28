#!/bin/bash

SESSION="mbsf-tutorial"
BASE_DIR=~/5gmag/open5gs_mbs_development
PANE_PGIDS=()

register_pane_pgid() {
  local pane_id="$1"
  local pane_pid
  local pgid

  # Get the PID of the pane's process
  pane_pid="$(tmux display-message -p -t "$pane_id" "#{pane_pid}")"

  # Get the process group ID
  pgid="$(ps -o pgid= -p "$pane_pid" | tr -d ' ')"

  # Append to list of PGIDs
  if [[ -n "$pgid" ]]; then
    PANE_PGIDS+=("$pgid")
  fi
}

cleanup() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    return
  fi

  # Terminate all process groups tied to panes from this session.
  for pgid in "${PANE_PGIDS[@]}"; do
    kill -TERM -- "-$pgid" 2>/dev/null || true
  done
  sleep 1
  for pgid in "${PANE_PGIDS[@]}"; do
    kill -KILL -- "-$pgid" 2>/dev/null || true
  done
}

trap cleanup EXIT

# End existing session if it exists

tmux kill-session -t $SESSION 2>/dev/null

# New session with new windows

tmux new-session -d -s $SESSION -n "NRF"
register_pane_pgid "$SESSION:NRF"
tmux send-keys -t $SESSION:NRF "$BASE_DIR/install/bin/open5gs-nrfd" Enter

tmux new-window -t $SESSION -n "SCP"
register_pane_pgid "$SESSION:SCP"
tmux send-keys -t $SESSION:SCP "$BASE_DIR/install/bin/open5gs-scpd" Enter

tmux new-window -t $SESSION -n "SMF"
register_pane_pgid "$SESSION:SMF"
tmux send-keys -t $SESSION:SMF "$BASE_DIR/install/bin/open5gs-smfd" Enter

tmux new-window -t $SESSION -n "UPF"
register_pane_pgid "$SESSION:UPF"
tmux send-keys -t $SESSION:UPF "sudo $BASE_DIR/install/bin/open5gs-upfd" Enter

tmux new-window -t $SESSION -n "AMF"
register_pane_pgid "$SESSION:AMF"
tmux send-keys -t $SESSION:AMF "$BASE_DIR/install/bin/open5gs-amfd" Enter

tmux new-window -t $SESSION -n "UDM"
register_pane_pgid "$SESSION:UDM"
tmux send-keys -t $SESSION:UDM "$BASE_DIR/install/bin/open5gs-udmd" Enter

tmux new-window -t $SESSION -n "MBSTF"
register_pane_pgid "$SESSION:MBSTF"
tmux send-keys -t $SESSION:MBSTF "sudo /usr/local/bin/open5gs-mbstfd" Enter

tmux new-window -t $SESSION -n "MBSF"
register_pane_pgid "$SESSION:MBSF"
tmux send-keys -t $SESSION:MBSF "sudo /usr/local/bin/open5gs-mbsfd -c $BASE_DIR/local-mbsf.yaml" Enter

# Connect session

tmux attach -t $SESSION