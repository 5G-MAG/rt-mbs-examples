#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================
SESSION="mbsf-tutorial"
OPEN5GS_BASE_DIR="${HOME}/5gmag/open5gs_mbs/install/bin"
MBSTF_BASE_DIR=/usr/local/bin
MBSF_BASE_DIR=/usr/local/bin
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Capture IDs for clean exit
PANE_PGIDS=()
PANE_PIDS=()

# ==============================================================================
# 2. THE ULTIMATE CLEANUP (Pre-Flight)
# ==============================================================================
echo "--- Performing Pre-Flight Cleanup ---"

# Kill any existing tmux sessions with this name
tmux kill-session -t "$SESSION" 2>/dev/null

# Kill any orphaned Open5GS processes hanging in the background
sudo pkill -9 open5gs-nrfd 2>/dev/null
sudo pkill -9 open5gs-scpd 2>/dev/null
sudo pkill -9 open5gs-smfd 2>/dev/null
sudo pkill -9 open5gs-upfd 2>/dev/null
sudo pkill -9 open5gs-amfd 2>/dev/null
sudo pkill -9 open5gs-udmd 2>/dev/null
sudo pkill -9 open5gs-mbstfd 2>/dev/null
sudo pkill -9 open5gs-mbsfd 2>/dev/null

# Small pause to allow ports to settle
sleep 1

# Ensure sudo is primed for the UPF
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo for the UPF. Please run 'sudo true' first."
    exit 1
fi

# ==============================================================================
# 3. FUNCTIONS
# ==============================================================================

register_pane_pgid() {
  local target="$1"
  local pane_pid=""
  for i in {1..10}; do
    pane_pid=$(tmux display-message -t "$target" -p "#{pane_pid}" 2>/dev/null)
    [[ -n "$pane_pid" ]] && break
    sleep 0.2
  done
  if [[ -n "$pane_pid" ]]; then
    PANE_PIDS+=("$pane_pid")
    local pgid=$(ps -o pgid= -p "$pane_pid" 2>/dev/null | tr -d ' ')
    [[ -n "$pgid" ]] && PANE_PGIDS+=("$pgid")
  fi
}

cleanup() {
  echo -e "\n--- Shutting down 5G components ---"
  # Kill main processes and their child groups
  for pid in "${PANE_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  for pgid in "${PANE_PGIDS[@]}"; do kill -TERM -- "-$pgid" 2>/dev/null; done

  sleep 1
  tmux kill-session -t "$SESSION" 2>/dev/null
  echo "Cleanup complete. System is clean."
}

# Trap exits (Ctrl+C or script finish) to trigger cleanup
trap cleanup EXIT

# ==============================================================================
# 4. EXECUTION (The Launch)
# ==============================================================================

echo "Starting NRF..."
tmux new-session -d -s "$SESSION" -n "NRF" "$OPEN5GS_BASE_DIR/open5gs-nrfd"
sleep 1
register_pane_pgid "$SESSION:NRF"

# Define components: "WindowName|Command"
COMPONENTS=(
  "SCP|$OPEN5GS_BASE_DIR/open5gs-scpd"
  "SMF|$OPEN5GS_BASE_DIR/open5gs-smfd"
  "UPF|sudo $OPEN5GS_BASE_DIR/open5gs-upfd"
  "AMF|$OPEN5GS_BASE_DIR/open5gs-amfd"
  "UDM|$OPEN5GS_BASE_DIR/open5gs-udmd"
  "MBSTF|$MBSTF_BASE_DIR/open5gs-mbstfd"
  "MBSF|$MBSF_BASE_DIR/open5gs-mbsfd -c $SCRIPT_DIR/local-mbsf.yaml"
)

for item in "${COMPONENTS[@]}"; do
  IFS="|" read -r NAME CMD <<< "$item"
  echo "Launching $NAME..."
  tmux new-window -t "$SESSION" -n "$NAME" "$CMD"
  register_pane_pgid "$SESSION:$NAME"
  sleep 0.3 # Paced start to prevent race conditions
done

# Check if session survived the launch
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "--- Success! All components launched ---"
  echo "Use 'Ctrl+B' then 'n' to cycle windows."
  tmux attach -t "$SESSION"
else
  echo "Error: Session failed to start. Check for port conflicts."
fi