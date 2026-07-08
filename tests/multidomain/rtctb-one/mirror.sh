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

set -e

INTERFACE="enp1s0"
AFFINITY="7"
RTPRIO="51"

IP_CIDR="192.168.1.101/24"


cd "$(dirname "$0")"


# Configure flow
sudo echo "> > > Starting RTC TB flow on ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null
./flow.sh ${INTERFACE}
sleep 10

sudo echo "> > > Removing XDP program on ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null
# Remove any stale XDP program
sudo xdp-loader unload -a ${INTERFACE} || true

sudo echo "> > > Configuring IP addresses on ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null
# We need an IP address in order for the LogJson packets to be sent
if ! ip addr show dev "${INTERFACE}" 2>/dev/null | grep -q "inet ${IP_CIDR}"; then
  sudo ip addr add "${IP_CIDR}" dev "${INTERFACE}"
fi

sudo echo "> > > Customizing config and running RTC TB app on ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null
source ../ptp/ptp.sh
CLOCK_AUX_IDX=$(first_hardware_phc_index ${INTERFACE})
CLOCK="CLOCK_AUX${CLOCK_AUX_IDX}"
sed -i "s/\(ApplicationClockId:[[:space:]]*\)[^ ]*/\1${CLOCK}/g" mirror.yaml

# Start one instance of mirror application
cp ../../../build/xdp_kern_*.o .

sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
../../../build/mirror -c mirror.yaml

exit 0
