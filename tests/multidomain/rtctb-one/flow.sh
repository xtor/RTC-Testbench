#!/bin/bash
#
# Copyright (C) 2023-2026 Linutronix GmbH
# Copyright (C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine <hector.blanco.alcaine@intel.com>
#   Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Tx and Rx traffic flows for Intel i225 for profinet scenario.
#

set -e


#
# Command line arguments.
#
INTERFACE=$1
CYCLETIME_NS=$2
BASETIME=$3

[ -z $INTERFACE ] && INTERFACE="enp1s0"        # default: enp1s0
[ -z $CYCLETIME_NS ] && CYCLETIME_NS="1000000" # default: 1ms
[ -z $BASETIME ] && BASETIME=0                 # default: next cycle


#
# Split traffic between TSN streams, real time and everything else.
#
ENTRY1_NS="500000"  # TSN High               PCP 6                      TC0-Q0
ENTRY2_NS="100000"  # Network Control        PCP 7 or PTP or LLDP       TC1-Q1
ENTRY3_NS=" 75000"  # Above Best-Effort      PCP 5 to PCP 1             TC2-Q2
ENTRY4_NS="325000"  # Best Effort (default)  PCP 0 or other untagged    TC3-Q3

  # Respect the same mapping as before We do not install a schedule but already map the traffic types to queues
  # Queue 0 / TC0: for real-time control, PCP 6
  # Queue 1 / TC1: for network critical traffic, PCP 7, LLDP, PTP
  # Queue 2 / TC2: for traffic above best effort
  # Queue 3 / TC3: for best effort
  # TC0: socket prio 6
  # TC1: socket prio 7
  # TC2: socket prios 1-5 and 8 to 15
  # TC3: socket prio 0 (default)

  # Apps
  # ptp4l: socket prio 7
  sudo tc qdisc replace dev "${INTERFACE}" handle 100 parent root \
    stab overhead 28 linklayer ethernet \
    taprio \
    num_tc 4 \
    map 3 2 2 2 2 2 0 1 2 2 2 2 2 2 2 2 \
    queues 1@0 1@1 1@2 1@3 \
    base-time "${BASETIME}" \
    sched-entry S 0x01 ${ENTRY1_NS} \
    sched-entry S 0x02 ${ENTRY2_NS} \
    sched-entry S 0x04 ${ENTRY3_NS} \
    sched-entry S 0x08 ${ENTRY4_NS} \
    flags 0x02


exit 0
