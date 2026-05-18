#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================
SESSION="mbstf-tutorial"
OPEN5GS_BASE_DIR="/home/fivegmag/Developer/open5gs_mbs/install/bin"
OPEN5GS_CONFIG_DIR="/home/fivegmag/Developer/open5gs_mbs/install/etc/open5gs"
MBSTF_BASE_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
MBSTF_CONFIG_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
MEDIA_SERVER_DIR="/home/fivegmag/Developer/rt-mbs-examples/express-mock-media-server"
LOG_DIR="/var/local/log/open5gs"

# Capture IDs for clean exit
PANE_PGIDS=()
PANE_PIDS=()

# ==============================================================================
# 2. PRE-FLIGHT CHECKS & CLEANUP
# ==============================================================================
echo "--- Initializing Setup ---"
# Prompt for sudo password once
read -s -p "[sudo] password for $(whoami): " SUDO_PASS
echo ""

# Validate password
echo "$SUDO_PASS" | sudo -S -v || { echo "Invalid password"; exit 1; }

echo "--- Ensuring log directory exists and is writable ---"
echo "$SUDO_PASS" | sudo -S mkdir -p "$LOG_DIR"
echo "$SUDO_PASS" | sudo -S chown -R $(whoami):$(whoami) "$LOG_DIR"

echo "--- Cleaning up existing processes and services ---"
tmux kill-session -t "$SESSION" 2>/dev/null

# 2a. Stop Background System Services
echo "Stopping Open5GS systemctl services..."
for SERVICE in nrfd scpd smfd upfd amfd mbstfd; do
    echo "$SUDO_PASS" | sudo -S systemctl stop open5gs-$SERVICE 2>/dev/null
done

# 2b. Kill Binary Instances
echo "Killing orphaned processes..."
echo "$SUDO_PASS" | sudo -S pkill -9 open5gs-nrfd open5gs-scpd open5gs-smfd open5gs-upfd open5gs-amfd open5gs-mbstfd 2>/dev/null
echo "$SUDO_PASS" | sudo -S fuser -k 3004/tcp 2>/dev/null

sleep 1

require_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }
}
require_executable() {
    [[ -x "$1" ]] || { echo "Missing executable: $1"; exit 1; }
}

require_command tmux
require_command npm
require_executable "$OPEN5GS_BASE_DIR/open5gs-nrfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-scpd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-smfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-upfd"
require_executable "$OPEN5GS_BASE_DIR/open5gs-amfd"
require_executable "$MBSTF_BASE_DIR/open5gs-mbstfd"

# ==============================================================================
# 3. FUNCTIONS
# ==============================================================================

# Wraps commands so the tmux window stays open on failure
wrap_cmd() {
    local cmd="$1"
    echo "bash -c \"$cmd || { echo; echo 'PROCESS FAILED'; read -p 'Press Enter to close...'; }\""
}

register_pane_pgid() {
    local target="$1"
    local pane_pid=""
    for _ in {1..10}; do
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
    echo -e "\n--- Shutting down MBSTF environment ---"
    for pid in "${PANE_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
    for pgid in "${PANE_PGIDS[@]}"; do kill -TERM -- "-$pgid" 2>/dev/null; done
    sleep 1
    tmux kill-session -t "$SESSION" 2>/dev/null
}

trap cleanup EXIT

# ==============================================================================
# 4. EXECUTION
# ==============================================================================

echo "Starting NRF..."
LAUNCH_NRF=$(wrap_cmd "$OPEN5GS_BASE_DIR/open5gs-nrfd")
tmux new-session -d -s "$SESSION" -n "NRF" "$LAUNCH_NRF"
sleep 1

# Verify session started before continuing
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Error: Tmux session failed to start. Check NRF logs or paths."
    exit 1
fi

register_pane_pgid "$SESSION:NRF"

# Define components: "WindowName|Command"
# Note the UPF uses the SUDO_PASS variable for non-interactive sudo
COMPONENTS=(
"SCP|$OPEN5GS_BASE_DIR/open5gs-scpd -c $OPEN5GS_CONFIG_DIR/scp.yaml"
    "SMF|$OPEN5GS_BASE_DIR/open5gs-smfd -c $OPEN5GS_CONFIG_DIR/smf.yaml"
    "UPF|echo '$SUDO_PASS' | sudo -S -E $OPEN5GS_BASE_DIR/open5gs-upfd -c $OPEN5GS_CONFIG_DIR/upf.yaml"
    "AMF|$OPEN5GS_BASE_DIR/open5gs-amfd -c $OPEN5GS_CONFIG_DIR/amf.yaml"
    "MBSTF|$MBSTF_BASE_DIR/open5gs-mbstfd -c $MBSTF_CONFIG_DIR/mbstf.yaml"
    "MediaServer|cd $MEDIA_SERVER_DIR && npm start"
)

for item in "${COMPONENTS[@]}"; do
    IFS="|" read -r NAME CMD <<< "$item"
    echo "Launching $NAME..."
    WRAPPED=$(wrap_cmd "$CMD")
    tmux new-window -t "$SESSION" -n "$NAME" "$WRAPPED"
    register_pane_pgid "$SESSION:$NAME"
    sleep 0.5
done

echo "--- Environment started successfully ---"
# Clear the password from memory for safety
unset SUDO_PASS
tmux attach -t "$SESSION"
