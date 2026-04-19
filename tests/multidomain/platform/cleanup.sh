#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright(C) 2026 Intel Corporation
# Copyright(C) 2021,2025 Linutronix GmbH
# Authors:
#   Hector Blanco Alcaine
#   Kurt Kanzenbach
# 
# Usage:
# ./cleanup.sh
#
# Clean-up interferring or stale processes from previous executions.


function cleanup () {

	echo '> > > Cleaning up all existing processes...' | sudo tee /dev/kmsg > /dev/null

	# Stop services
	sudo systemctl stop systemd-timesyncd || true
	sudo systemctl stop ntpd || true
	sudo systemctl stop chrony || true

	# Kill already running daemons
	sudo pkill -KILL --exact phc2sys || true
	sudo pkill -KILL --exact ptp4l   || true

	# Kill stale instances
	sudo pkill --full reference.yaml
	sudo pkill --full mirror.yaml

	sleep 3

}

cleanup
ps -eLo psr,rtprio,pid,tid,args | sort -nk1  | grep -v '\['
