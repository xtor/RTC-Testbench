#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
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
    tmux split-window -v -t "${TARGET}.1"
    tmux select-layout -t "$TARGET" even-horizontal

    # Set pane titles
    tmux select-pane -T "RTC TB" -t "${TARGET}.0"
    tmux select-pane -T "UDP Translator" -t "${TARGET}.1"
    tmux select-pane -T "Congestion" -t "${TARGET}.2"

    # Bind Prefix + Q (Shift+q) to instantly kill the window without a prompt
    tmux bind-key Q kill-window

    # First start RTC TB
    tmux send-keys -t "${TARGET}.0" "cd ${TBDIR}" C-m
    tmux send-keys -t "${TARGET}.0" "clear" C-m 

    if [[ "${NODE}" == "mirror" ]]; then
        tmux send-keys -t "${TARGET}.0" "sudo ./mirror.sh"
    elif [[ "${NODE}" == "reference" ]]; then
        tmux send-keys -t "${TARGET}.0" "sudo ./ref.sh"
    fi

    tmux send-keys -t "${TARGET}.1" "python3 ../../scripts/udp_json_to_fixed.py ${MIRROR_IP} ${PORT} default" C-m

    if [[ "${NODE}" == "mirror" ]]; then
        tmux send-keys -t "${TARGET}.2" "iperf3 --server --bind-dev ${MIRROR_INTERFACE}" C-m
    elif [[ "${NODE}" == "reference" ]]; then
        tmux send-keys -t "${TARGET}.2" "iperf3 --client ${MIRROR_IP} -u -b 1G -t 0" C-m
    fi

    tmux select-pane -t "${TARGET}.0"

    if [ $ATTACH -eq 1 ]; then
        tmux attach-session -t "$SESSION_NAME"
    else
        tmux select-window -t "$TARGET"
    fi
}


if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [mirror|reference] [one|two|three]"
    exit 1
fi

NODE="$1"
INSTANCE="$2"


if [[ "${INSTANCE}" == "one" ]]; then
    TBDIR="rtctb-one"
    MIRROR_IP="192.168.001.101"
    PORT="60601"
elif [[ "${INSTANCE}" == "two" ]]; then
    TBDIR="rtctb-two"
    MIRROR_IP="192.168.002.101"
    PORT="60602"
elif [[ "${INSTANCE}" == "three" ]]; then
    TBDIR="rtctb-three"
    MIRROR_IP="192.168.003.101"
    PORT="60603"
else
    echo "Usage: $0 [mirror|reference] [one|two|three]"
    exit 1
fi
MIRROR_INTERFACE="$(cd ${TBDIR} && grep 'INTERFACE=' mirror.sh  | sed 's/INTERFACE=\"\(.*\)\"$/\1/g')"


SESSION_NAME="RTC Testbench"
WINDOW_NAME="[RTC TB ${INSTANCE}]"
sudo --validate
setup_rtctb_window ${NODE}
