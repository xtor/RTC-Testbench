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
        tmux send-keys -t "${TARGET}.0" "sudo ./mirror.sh ${INTERFACE}"
    elif [[ "${NODE}" == "reference" ]]; then
        tmux send-keys -t "${TARGET}.0" "sudo ./ref.sh ${INTERFACE}"
    fi

    tmux send-keys -t "${TARGET}.1" "python3 ../../scripts/udp_json_to_fixed.py ${MIRROR_IP} ${PORT} ${MEASUREMENT}" C-m

    if [[ "${NODE}" == "mirror" ]]; then
        tmux send-keys -t "${TARGET}.2" "iperf3 -s" C-m
    elif [[ "${NODE}" == "reference" ]]; then
        tmux send-keys -t "${TARGET}.2" "iperf3 -c ${MIRROR_IP} -u -b 1G -t 0" C-m
    fi

    tmux select-pane -t "${TARGET}.0"

    if [ $ATTACH -eq 1 ]; then
        tmux attach-session -t "$SESSION_NAME"
    else
        tmux select-window -t "$TARGET"
    fi
}


if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [mirror|reference] [crypto|metrics]"
    exit 1
fi

NODE="$1"
TB="$2"


if [[ "${TB}" == "crypto" ]]; then
    TBDIR="rtctb-crypto"
    INTERFACE="enp1s0"
    REF_IP="192.168.100.102"
    MIRROR_IP="192.168.100.101"
    PORT="60600"
    MEASUREMENT="default"
elif [[ "${TB}" == "metrics" ]]; then
    TBDIR="rtctb-metrics"
    INTERFACE="enp2s0"
    REF_IP="192.168.100.104"
    MIRROR_IP="192.168.100.103"
    PORT="60601"
    MEASUREMENT="soc"
else
    echo "Usage: $0 [mirror|reference] [crypto|metrics]"
    exit 1
fi


SESSION_NAME="RTC Testbench"
WINDOW_NAME="[${TB}]"
sudo --validate
setup_rtctb_window ${INTERFACE} ${NODE}
