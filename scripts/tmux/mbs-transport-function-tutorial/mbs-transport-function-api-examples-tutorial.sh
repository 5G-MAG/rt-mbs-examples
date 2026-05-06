#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================
SESSION="mbstf-tutorial"
# Verified absolute paths
OPEN5GS_BASE_DIR="${HOME}/5gmag/open5gs_mbs/install/bin"
MBSTF_BASE_DIR=/usr/local/bin
MEDIA_SERVER_DIR="${HOME}/5gmag/rt-mbs-examples/express-mock-media-server"

PANE_PGIDS=()
PANE_PIDS=()

# ==============================================================================
# 2. PRE-FLIGHT CLEANUP (Prevent Port Conflicts)
# ==============================================================================
echo "--- Cleaning up existing processes ---"
tmux kill-session -t "$SESSION" 2>/dev/null

# Kill Open5GS components
sudo pkill -9 open5gs-nrfd 2>/dev/null
sudo pkill -9 open5gs-scpd 2>/dev/null
sudo pkill -9 open5gs-smfd 2>/dev/null
sudo pkill -9 open5gs-upfd 2>/dev/null
sudo pkill -9 open5gs-amfd 2>/dev/null
sudo pkill -9 open5gs-mbstfd 2>/dev/null

# Kill Node/Media Server processes
pkill -9 -f "node" 2>/dev/null

sleep 1

if ! sudo -n true 2>/dev/null; then
    echo "Sudo access required for UPF. Please run 'sudo true' first."
    exit 1
fi

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name"
    exit 1
  fi
}

require_executable() {
  local executable_path="$1"
  if [[ ! -x "$executable_path" ]]; then
    echo "Required executable not found or not executable: $executable_path"
    exit 1
  fi
}

require_dir() {
  local dir_path="$1"
  if [[ ! -d "$dir_path" ]]; then
    echo "Required directory not found: $dir_path"
    exit 1
  fi
}

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Required file not found: $file_path"
    exit 1
  fi
}

require_command tmux
require_command npm
require_executable "$OPEN5GS_BASE_DIR/open5gs-nrfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-scpd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-smfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-upfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-amfd"
require_executable "$MBSTF_BASE_DIR/open5gs-mbstfd"
require_dir "$MEDIA_SERVER_DIR"
require_file "$MEDIA_SERVER_DIR/package.json"

# ==============================================================================
# 3. FUNCTIONS
# ==============================================================================

register_pane_pgid() {
  local target="$1"
  local pane_pid=""
  local pgid=""
  # Wait for tmux to assign the PID
  for _ in {1..10}; do
    pane_pid=$(tmux display-message -t "$target" -p "#{pane_pid}" 2>/dev/null)
    [[ -n "$pane_pid" ]] && break
    sleep 0.2
  done
  if [[ -n "$pane_pid" ]]; then
    PANE_PIDS+=("$pane_pid")
    # Capture PGID (crucial for npm/node sub-processes)
    pgid=$(ps -o pgid= -p "$pane_pid" 2>/dev/null | tr -d ' ')
    [[ -n "$pgid" ]] && PANE_PGIDS+=("$pgid")
  fi
}

cleanup() {
  echo -e "\n--- Shutting down MBSTF environment ---"
  # Kill main PIDs and child process groups
  for pid in "${PANE_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  for pgid in "${PANE_PGIDS[@]}"; do kill -TERM -- "-$pgid" 2>/dev/null; done

  sleep 1
  tmux kill-session -t "$SESSION" 2>/dev/null
  echo "All services stopped."
}

trap cleanup EXIT

# ==============================================================================
# 4. EXECUTION
# ==============================================================================

echo "Starting NRF..."
tmux new-session -d -s "$SESSION" -n "NRF" "$OPEN5GS_BASE_DIR/open5gs-nrfd"
sleep 1
register_pane_pgid "$SESSION:NRF"

# Components List: "WindowName|Command"
COMPONENTS=(
  "SCP|$OPEN5GS_BASE_DIR/open5gs-scpd"
  "SMF|$OPEN5GS_BASE_DIR/open5gs-smfd"
  "UPF|sudo $OPEN5GS_BASE_DIR/open5gs-upfd"
  "AMF|$OPEN5GS_BASE_DIR/open5gs-amfd"
  "MBSTF|$MBSTF_BASE_DIR/open5gs-mbstfd"
  "MediaServer|cd $MEDIA_SERVER_DIR && npm start"
)

for item in "${COMPONENTS[@]}"; do
  IFS="|" read -r NAME CMD <<< "$item"
  echo "Launching $NAME..."
  tmux new-window -t "$SESSION" -n "$NAME" "$CMD"
  register_pane_pgid "$SESSION:$NAME"
  sleep 0.3
done

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "--- Environment started successfully ---"
  tmux attach -t "$SESSION"
else
  echo "Error: Session failed. Ensure all paths and npm dependencies are correct."
fi