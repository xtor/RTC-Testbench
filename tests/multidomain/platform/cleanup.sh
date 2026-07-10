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


function reset_cgroup () {

  SLICE_NAME=$1

  sudo systemctl stop "${SLICE_NAME}" || true
  # FIXME: avoid deleting potential files already existing
  sudo rm -f /etc/systemd/system/${SLICE_NAME}

  sudo mkdir -p /etc/systemd/system
  cat <<EOF | sudo tee /etc/systemd/system/${SLICE_NAME} > /dev/null
[Unit]
Description=Realtime Slice for Benchmark Isolation

[Slice]
# Allocate the isolated cores
AllowedCPUs=4-11
# Mandatory: assign memory nodes (usually 0 on non-NUMA)
AllowedMemoryNodes=0
Delegate=yes
DisableControllers=cpu io memory pids
CPUAccounting=no
MemoryAccounting=no
IOAccounting=no
TasksAccounting=no
EOF

  # Start the slice transiently so the path exists before writing to sysfs
  sudo systemctl start "${SLICE_NAME}"
  sudo systemctl daemon-reload

  # Strictly isolate the partition
  echo "isolated" | sudo tee "/sys/fs/cgroup/${SLICE_NAME}/cpuset.cpus.partition" > /dev/null

}


function cleanup () {

	echo '> > > Cleaning up all existing processes...' | sudo tee /dev/kmsg > /dev/null

	# Stop services
	sudo systemctl stop systemd-timesyncd || true
	sudo systemctl stop ntpd || true
	sudo systemctl stop chrony || true

	# Kill already running daemons
	sudo pkill -KILL --exact phc2sys || true
	sudo pkill -KILL --exact ptp4l   || true
	sudo pkill -KILL --exact chronyd || true
	# Delete the chronyd configuration file
	sudo rm -rf /tmp/multidomain

	# Kill stale instances
	sudo pkill --full reference.yaml
	sudo pkill --full mirror.yaml


	sleep 3

}

cleanup
reset_cgroup "realtime.slice"
ps -eLo psr,rtprio,pid,tid,args | sort -nk1  | grep -v '\['
