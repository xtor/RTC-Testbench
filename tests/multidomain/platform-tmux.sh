#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Usage:
# ./platform-tmux.sh [mirror|reference]
#
#  Provides a helper tmux window to bring-up and tune the platform and
#  interfaces. It also takes care of cloning and compiling the dependencies if
#  needed. This way the PTP tmux helper can be used independently.
#
#  It creates a 3 rows x 2 columns matrix of panes, consisting of:
#  - 1st row: console, dmesg
#  - 2nd row: two consoles
#  - 3rd row: two consoles
#
#  The script can be called from within a tmux session or directly from a
#  standalone shell.
#
#  A shortcut Ctrl-B + Shift-Q closes all the panes and the window.
#


function setup_platform_window () {

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
    tmux select-pane -T "enp1s0" -t "${TARGET}.0"
    tmux select-pane -T "dmesg" -t "${TARGET}.1"
    tmux select-pane -T "enp2s0" -t "${TARGET}.2"
    tmux select-pane -T "Console 1" -t "${TARGET}.3" 
    tmux select-pane -T "enp3s0" -t "${TARGET}.4"
    tmux select-pane -T "Console 2" -t "${TARGET}.5"

    # Bind Prefix + Q (Shift+q) to instantly kill the window without a prompt
    tmux bind-key Q kill-window

    tmux send-keys -t "${TARGET}.1" "sudo dmesg -w" C-m

    # Reset interface enp1s0
    tmux send-keys -t "${TARGET}.0" "source ptp/ptp.sh" C-m
    tmux send-keys -t "${TARGET}.0" "clear" C-m
    tmux send-keys -t "${TARGET}.0" "platform/reset.sh enp1s0 && tune_timestamping enp1s0" C-m

    # Reset interface enp2s0
    tmux send-keys -t "${TARGET}.2" "source ptp/ptp.sh" C-m
    tmux send-keys -t "${TARGET}.2" "clear" C-m
    tmux send-keys -t "${TARGET}.2" "platform/reset.sh enp2s0 && tune_timestamping enp2s0" C-m

    # Reset interface enp3s0
    tmux send-keys -t "${TARGET}.4" "source ptp/ptp.sh" C-m
    tmux send-keys -t "${TARGET}.4" "clear" C-m
    tmux send-keys -t "${TARGET}.4" "platform/reset.sh enp3s0 && tune_timestamping enp3s0" C-m

   
    if [ $ATTACH -eq 1 ]; then
        tmux attach-session -t "$SESSION_NAME"
    else
        tmux select-window -t "$TARGET"
    fi
}


if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [mirror|reference]"
    exit 1
fi

NODE="$1"


# Checkout and compile LinuxPTP's tip in case it does not exist
# This way we guarantee multiple time domain and aux clock support is available.
if [ ! -d "./linuxptp" ]; then
  git clone https://github.com/richardcochran/linuxptp.git
  cd linuxptp
  make
  cd ..
fi

# Checkout and compile chrony's tip in case it does not exist
if [ ! -d "./chrony" ]; then
  git clone https://github.com/mlichvar/chrony.git
  cd chrony
  ./configure
  make
  cd ..
fi


if [[ "${NODE}" == "mirror" ]]; then
    ROLE="master"
elif [[ "${NODE}" == "reference" ]]; then
    ROLE="slave"
else
    echo "Usage: $0 [mirror|reference]"
    exit 1
fi


SESSION_NAME="Platform"
WINDOW_NAME="[${NODE} Platform]"
sudo --validate
platform/cleanup.sh
setup_platform_window ${NODE}
