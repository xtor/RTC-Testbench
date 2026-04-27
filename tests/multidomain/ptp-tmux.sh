#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Usage:
# ./ptp-tmux.sh <INTERFACE> [mirror|reference]
#
#  Provides a helper tmux window to bring-up and monitor the CMLDS and domain
#  PTP instances, and the related host synchronization using phc2sys and chrony.
#
#  It creates a 3 rows x 2 columns matrix of panes, consisting of:
#  - 1st row: CMLDS ptp4l, dmesg
#  - 2nd row: GT ptp4l, GT host sync
#  - 3rd row: WC ptp4l, WC host sync
#
#  The script can be called from within a tmux session or directly from a
#  standalone shell.
#
#  A shortcut Ctrl-B + Shift-Q closes all the panes and the window.
#


function setup_timesynch_window () {

    # Check if we are inside an active tmux session
    if [ -z "$TMUX" ]; then
        tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME"
        TARGET="$SESSION_NAME:$WINDOW_NAME"
        ATTACH=1
    else
        TARGET=$(tmux new-window -P -d -n "$WINDOW_NAME" -F "#{window_id}")
        ATTACH=0
    fi

    # Enable titles
    tmux set-option -w -t "$TARGET" pane-border-status top
    tmux set-option -w -t "$TARGET" pane-border-format "[ #T ]"

    # Create layout
    tmux split-window -v -t "${TARGET}.0"
    tmux split-window -v -t "${TARGET}.1"
    tmux select-layout -t "$TARGET" even-vertical

    tmux split-window -h -p 50 -t "${TARGET}.0"
    tmux split-window -h -p 50 -t "${TARGET}.2"
    tmux split-window -h -p 50 -t "${TARGET}.4"

    # Set pane titles
    tmux select-pane -T "CMLDS" -t "${TARGET}.0"
    tmux select-pane -T "dmesg" -t "${TARGET}.1"
    tmux select-pane -T "GT Domain" -t "${TARGET}.2"
    tmux select-pane -T "GT vPHC <-> System Time" -t "${TARGET}.3" 
    tmux select-pane -T "WC Domain" -t "${TARGET}.4"
    tmux select-pane -T "WC PHC <-> CLOCK_AUX" -t "${TARGET}.5"

    # Bind Prefix + Q (Shift+q) to instantly kill the window without a prompt
    tmux bind-key Q kill-window

    tmux send-keys -t "${TARGET}.1" "sudo dmesg -w" C-m

    # First start CMLDS
    tmux send-keys -t "${TARGET}.0" "source ptp/ptp.sh" C-m 
    tmux send-keys -t "${TARGET}.0" "clear" C-m 
    tmux send-keys -t "${TARGET}.0" "platform/cleanup.sh && platform/reset.sh ${INTERFACE} && run_cmlds ${INTERFACE}"

    # Then the Global Time domain
    tmux send-keys -t "${TARGET}.2" "source ptp/ptp.sh" C-m 
    tmux send-keys -t "${TARGET}.2" "clear" C-m 
    tmux send-keys -t "${TARGET}.2" "run_gt ${INTERFACE} ${ROLE}"
    
    # Then the Working Clock domain
    tmux send-keys -t "${TARGET}.4" "source ptp/ptp.sh" C-m 
    tmux send-keys -t "${TARGET}.4" "clear" C-m 
    tmux send-keys -t "${TARGET}.4" "run_wc ${INTERFACE} ${ROLE}"

    tmux send-keys -t "${TARGET}.3" "source ptp/ptp.sh" C-m 
    tmux send-keys -t "${TARGET}.3" "clear" C-m 

    if [[ "${NODE}" == "mirror" ]]; then
        # Synchronize the Global Time to the system time
        tmux send-keys -t "${TARGET}.3" "run_gt2phc ${INTERFACE} ${ROLE}"
    elif [[ "${NODE}" == "reference" ]]; then
        # Synchronize the system time to the Global Time
        tmux send-keys -t "${TARGET}.3" "run_phc2gt ${INTERFACE} ${ROLE}"
    fi

    # Synchronize CLOCK_AUX0 to the Working Clock
    tmux send-keys -t "${TARGET}.5" "source ptp/ptp.sh" C-m 
    tmux send-keys -t "${TARGET}.5" "clear" C-m 
    tmux send-keys -t "${TARGET}.5" "run_phc2wc ${INTERFACE} ${ROLE}"
   
    if [ $ATTACH -eq 1 ]; then
        tmux attach-session -t "$SESSION_NAME"
    else
        tmux select-window -t "$TARGET"
    fi
}


if [ "$#" -ne 2 ]; then
    echo "Usage: $0 INTERFACE [mirror|reference]"
    exit 1
fi

INTERFACE="$1"
NODE="$2"


if [[ "${NODE}" == "mirror" ]]; then
    ROLE="master"
elif [[ "${NODE}" == "reference" ]]; then
    ROLE="slave"
else
    echo "Usage: $0 INTERFACE [mirror|reference]"
    exit 1
fi


SESSION_NAME="Multidomain"
WINDOW_NAME="${NODE} ${INTERFACE} Sync"
sudo --validate
setup_timesynch_window ${INTERFACE} ${NODE}
