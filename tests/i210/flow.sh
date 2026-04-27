#!/bin/bash
#
# Copyright (C) 2026 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Tx and Rx traffic flows for Intel i210 for testing XDP busy polling.
#

set -e

source ../lib/common.sh
source ../lib/igb.sh

#
# Command line arguments.
#
INTERFACE=$1
CYCLETIME_NS=$2

[ -z $INTERFACE ] && INTERFACE="enp1s0"        # default: enp1s0
[ -z $CYCLETIME_NS ] && CYCLETIME_NS="1000000" # default: 1ms

load_kernel_modules

napi_defer_hard_irqs "${INTERFACE}" "${CYCLETIME_NS}"

igb_start "${INTERFACE}"

#
# Tx Assignment with strict priority in HW.
#
# PCP 6   - Tx Q 0 - TSN High
# PCP 5   - Tx Q 1 - TSN Low
# PCP 4   - Tx Q 2 - RTC
# PCP 3/X - Tx Q 3 - RTA and Everything else
#
tc qdisc replace dev ${INTERFACE} handle 100 parent root mqprio num_tc 4 \
  map 3 3 3 3 3 2 1 0 3 3 3 3 3 3 3 3 \
  queues 1@0 1@1 1@2 1@3 \
  hw 1

#
# Rx Queues Assignment.
#
# Rx Q 0 - TSN High
# Rx Q 1 - TSN Low
# Rx Q 2 - RTC
# Rx Q 3 - All Traffic
#
RXQUEUES=(3 0 1 2 3 3 3 3 3 3)
igb_rx_queues_assign "${INTERFACE}" RXQUEUES

igb_end "${INTERFACE}"

setup_irqs "${INTERFACE}"

exit 0
