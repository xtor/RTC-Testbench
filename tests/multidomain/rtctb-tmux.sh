#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Usage:
# ./rtctb-tmux.sh <INTERFACE> [mirror|reference]
#
#  Provides a helper tmux window to bring-up and monitor an instance of the
#  Linux Real Time Communications Testbench running on a given interface.
#
#  It creates 2 vertical panes, holding:
#  - 1st pane: RTC Testbench
#  - 2nd pane: console
#
#  The script can be called from within a tmux session or directly from a
#  standalone shell.
#
#  A shortcut Ctrl-B + Shift-Q closes all the panes and the window.
#


function setup_rtctb_window () {

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
    tmux split-window -h -t "${TARGET}.0"
    tmux select-layout -t "$TARGET" even-horizontal

    # Set pane titles
    tmux select-pane -T "RTC TB" -t "${TARGET}.0"
    tmux select-pane -T "Debug" -t "${TARGET}.1"

    # Bind Prefix + Q (Shift+q) to instantly kill the window without a prompt
    tmux bind-key Q kill-window

    # First start RTC TB
    tmux send-keys -t "${TARGET}.0" "cd rtctb0" C-m 
    tmux send-keys -t "${TARGET}.0" "clear" C-m 

    if [[ "${NODE}" == "mirror" ]]; then
        tmux send-keys -t "${TARGET}.0" "sudo ./mirror.sh ${INTERFACE}"
    elif [[ "${NODE}" == "reference" ]]; then
        tmux send-keys -t "${TARGET}.0" "sudo ./ref.sh ${INTERFACE}"
    fi
   
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
WINDOW_NAME="${NODE} ${INTERFACE} TB0"
sudo --validate
setup_rtctb_window ${INTERFACE} ${NODE}
