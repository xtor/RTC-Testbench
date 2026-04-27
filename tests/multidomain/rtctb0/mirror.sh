#!/bin/bash
#
# Copyright (C) 2023 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#

set -e

INTERFACE="enp1s0"
AFFINITY="6"
RTPRIO="51"

cd "$(dirname "$0")"


# Configure flow
sudo echo "> > > Starting RTC TB flow on ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null
sudo ethtool -K ${INTERFACE} ntuple off
./flow.sh ${INTERFACE}
sleep 10

source ../ptp/ptp.sh
CLOCK_AUX_IDX=$(first_hardware_phc_index ${INTERFACE})
CLOCK="CLOCK_AUX${CLOCK_AUX_IDX}"
sed -i "s/\(ApplicationClockId:[[:space:]]*\)[^ ]*/\1${CLOCK}/g" mirror.yaml

# Start one instance of mirror application
cp ../../../build/xdp_kern_*.o .

sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
../../../build/mirror -c mirror.yaml

exit 0
