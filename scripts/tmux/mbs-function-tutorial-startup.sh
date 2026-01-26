#!/bin/bash

SESSION="mbsf-tutorial"
BASE_DIR=~/5gmag/open5gs_mbs_development

# End existing session if it exists

tmux kill-session -t $SESSION 2>/dev/null

# New session with new windows

tmux new-session -d -s $SESSION -n "NRF"
tmux send-keys -t $SESSION:NRF "$BASE_DIR/install/bin/open5gs-nrfd" Enter

tmux new-window -t $SESSION -n "SCP"
tmux send-keys -t $SESSION:SCP "$BASE_DIR/install/bin/open5gs-scpd" Enter

tmux new-window -t $SESSION -n "SMF"
tmux send-keys -t $SESSION:SMF "$BASE_DIR/install/bin/open5gs-smfd" Enter

tmux new-window -t $SESSION -n "UPF"
tmux send-keys -t $SESSION:UPF "sudo $BASE_DIR/install/bin/open5gs-upfd" Enter

tmux new-window -t $SESSION -n "AMF"
tmux send-keys -t $SESSION:AMF "$BASE_DIR/install/bin/open5gs-amfd" Enter

tmux new-window -t $SESSION -n "UDM"
tmux send-keys -t $SESSION:UDM "$BASE_DIR/install/bin/open5gs-udmd" Enter

tmux new-window -t $SESSION -n "MBSTF"
tmux send-keys -t $SESSION:MBSTF "sudo /usr/local/bin/open5gs-mbstfd" Enter

tmux new-window -t $SESSION -n "MBSF"
tmux send-keys -t $SESSION:MBSF "sudo /usr/local/bin/open5gs-mbsfd -c $BASE_DIR/local-mbsf.yaml" Enter

# Connect session

tmux attach -t $SESSION