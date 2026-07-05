#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2020-2025 Linutronix GmbH
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
#   Kurt Kanzenbach
# 
# Usage:
# ./reset.sh [INTERFACE]
#
#  Resets the auxclock, vclock and NIC for a pristine execution.
#
#  In addition, the NICs are pre-configured to avoid disruptions to the link
#  when running the flow scripts.
#

set -e

PHC_CTL="${HOME}/devel/demo/ett26/src/linuxptp/phc_ctl"




#
# igc_rx_queues_assign($interface, @rx_queues)
#
# Rx queues assignment based on PCP values and EtherType.
#
igc_rx_queues_assign() {
  local interface=$1
  local -n rx_queues=$2
  local len

  len=${#rx_queues[@]}

  if [ "$len" -ne 10 ]; then
    echo "igc_rx_queues_assign: rx_queues array len has to be 10!"
    return
  fi

  sudo ethtool -K "${interface}" ntuple on

  # PCP 7
  sudo ethtool -N "${interface}" flow-type ether vlan 0xe000 m 0x1fff action "${rx_queues[0]}"

  # PCP 6
  sudo ethtool -N "${interface}" flow-type ether vlan 0xc000 m 0x1fff action "${rx_queues[1]}"

  # PCP 5
  sudo ethtool -N "${interface}" flow-type ether vlan 0xa000 m 0x1fff action "${rx_queues[2]}"

  # PCP 4
  sudo ethtool -N "${interface}" flow-type ether vlan 0x8000 m 0x1fff action "${rx_queues[3]}"

  # PCP 3
  sudo ethtool -N "${interface}" flow-type ether vlan 0x6000 m 0x1fff action "${rx_queues[4]}"

  # PCP 2
  sudo ethtool -N "${interface}" flow-type ether vlan 0x4000 m 0x1fff action "${rx_queues[5]}"

  # PCP 1
  sudo ethtool -N "${interface}" flow-type ether vlan 0x2000 m 0x1fff action "${rx_queues[6]}"

  # PCP 0
  sudo ethtool -N "${interface}" flow-type ether vlan 0x0000 m 0x1fff action "${rx_queues[7]}"

  #
  # PTP and LLDP are transmitted untagged. Steer them via EtherType.
  #
  sudo ethtool -N "${interface}" flow-type ether proto 0x88f7 action "${rx_queues[8]}"
  sudo ethtool -N "${interface}" flow-type ether proto 0x88cc action "${rx_queues[9]}"
}


function reset_auxclocks () {
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/0/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/1/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/2/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/3/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/4/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/5/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/6/aux_clock_enable > /dev/null
  echo 0 | sudo tee /sys/kernel/time/aux_clocks/7/aux_clock_enable > /dev/null
}


function reset_vclocks () {
  	INTERFACE="$1"

	# E.g. ptp0
	PTP_NAME="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"

	# Delete any previously created vclocks
	echo 0 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/n_vclocks > /dev/null
}


function reset_driver () {

  local INTERFACE=$1

  local STATE_FILE="/sys/class/net/${INTERFACE}/operstate"
  local DRIVER_LINK="/sys/class/net/${INTERFACE}/device/driver/module"
  local MODULE_NAME="$(basename $(realpath ${DRIVER_LINK}))"
  local DEVICE_LINK="/sys/class/net/${INTERFACE}/device"
  local PCI_BDF="$(basename $(realpath ${DEVICE_LINK}))"

  local NUM_IGC_DEVICES="$(find /sys/bus/pci/drivers/igc/ -maxdepth 1 -type l -name '*:*' | wc -l)"

  local LINK_PARTNER_STATE=$(cat "${STATE_FILE}")

  sudo echo "> > > Resetting: ${INTERFACE}..." | sudo tee /dev/kmsg > /dev/null

  # Bring the interface down
  sudo ip link set dev "${INTERFACE}" down
  while [ -f "$STATE_FILE" ] && grep -q "up" "$STATE_FILE"; do
    sleep 0.1
  done

  # FIXME: introduce a maximum number of iterations
  # to cover for cases where the machines are back to back and the link partner
  # did not come up
  if [[ ${NUM_IGC_DEVICES} -eq 1 ]]; then

    # Unload the module
    sudo rmmod "${MODULE_NAME}"
    while [ -d "/sys/class/net/${INTERFACE}" ] && [ -e "$DRIVER_LINK" ]; do
      # Sleep briefly to avoid CPU thrashing if the module is busy/stubborn
      sleep 0.1
    done

    # Load the module
    sudo modprobe "${MODULE_NAME}"
    while [ ! -d "/sys/class/net/${INTERFACE}" ] || [ ! -e "$DRIVER_LINK" ]; do
      sleep 0.1
    done

  # If the driver is shared across multiple devices, we cannot just rmmod it
  elif [[ ${NUM_IGC_DEVICES} -gt 1 ]]; then

    # Unbind the module
    echo "${PCI_BDF}" | sudo tee /sys/bus/pci/drivers/igc/unbind > /dev/null
    # Trigger hardware FLR
    # echo 1 > /sys/bus/pci/devices/0000:01:00.0/reset
    while [ -d "/sys/class/net/${INTERFACE}" ] && [ -e "$DRIVER_LINK" ]; do
      # Sleep briefly to avoid CPU thrashing if the module is busy/stubborn
      sleep 0.1
    done

    # Bind the module
    echo "${PCI_BDF}" | sudo tee /sys/bus/pci/drivers/igc/bind > /dev/null
    while [ ! -d "/sys/class/net/${INTERFACE}" ] || [ ! -e "$DRIVER_LINK" ]; do
      sleep 0.1
    done

  fi

  # Bring the interface up
  sudo ip link set dev "${INTERFACE}" up
  # Only wait for the interface to come up if the link parter was up
  if [[ ${LINK_PARTNER_STATE} == "up" ]]; then
    while [ -f "$STATE_FILE" ] && grep -q "down" "$STATE_FILE"; do
      sleep 0.5
    done
  fi

}


function preconfigure_interface () {

  local INTERFACE=$1

  # Once the driver is reset and the device is up again, proceed to configure
  # the link. We do not perform the configuration before bringing the link up
  # because some drivers do not support it.

  # Set Energy Efficient Ethernet off
  sudo ethtool --set-eee "${INTERFACE}" eee off
  while sudo ethtool --show-eee "${INTERFACE}" | grep -q "EEE status: enabled"; do
    sleep 0.5
  done

  # Set the link speed
  sudo ethtool -s "${INTERFACE}" speed "${SPEED}" autoneg on duplex full

  #
  # Tx Settings
  #

  # Set the physical PHC to zero
  # The physical PHC will be the Working Clock, used to drive the Qbv schedule
  # We wait 5s to make sure the PHC is up-to-date when we continue executing 
  sudo "${PHC_CTL}" "${INTERFACE}" set 0.0 > /dev/null
  sleep 5

  # We do not install a schedule but already map the traffic types to queues
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
  local BASETIME=0
  sudo tc qdisc replace dev "${INTERFACE}" handle 100 parent root \
    stab overhead 28 linklayer ethernet \
    taprio \
    num_tc 4 \
    map 3 2 2 2 2 2 0 1 2 2 2 2 2 2 2 2 \
    queues 1@0 1@1 1@2 1@3 \
    base-time "${BASETIME}" \
    sched-entry S 0x0F 1000000000 \
    flags 0x02

  # Disable Interrupt Coalescing (rx-usecs disables both rx and tx)
  sudo ethtool -C "${INTERFACE}" rx-usecs 0

  # Enable Threaded NAPI
  echo 1 | sudo tee /sys/class/net/${INTERFACE}/threaded > /dev/null


  # Increase the priority of the timestamping interrupt handler
  IRQ_TS=$(ls -1 /sys/class/net/${INTERFACE}/device/msi_irqs/ | head -1)
  IRQ_TS_PID=$(pgrep -a "irq/${IRQ_TS}-${INTERFACE}" | cut -f1 -d' ')
  sudo chrt -f -p 95 "${IRQ_TS_PID}"

}


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


# TODO: operate on a list of interfaces provided as arguments to the script

function reset_interface () {
  INTERFACE="$1"

  reset_driver "${INTERFACE}"
  preconfigure_interface "${INTERFACE}"

}


function platform_reset () {
  INTERFACE="$1"


  if [[ -z "$1" ]]; then

    reset_auxclocks &

    reset_interface enp1s0
    preconfigure_interface enp1s0

    reset_interface enp2s0
    preconfigure_interface enp2s0

    reset_interface enp3s0
    preconfigure_interface enp3s0

    reset_vclocks enp1s0
    reset_vclocks enp2s0
    reset_vclocks enp3s0

    reset_cgroup "realtime.slice"

    wait

  else

    reset_auxclocks &
    
    reset_interface ${INTERFACE}
    preconfigure_interface ${INTERFACE}
    
    reset_vclocks ${INTERFACE}


    wait

  fi

  sleep 10
}



[ -z ${SPEED} ] && SPEED="1000"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 INTERFACE0 ... INTERFACEn"
  exit 1
fi

# We wait 5s to make sure the system time is up-to-date when we continue executing 
# Make sure /etc/default/ntpdate is properly configured
sudo ntpdate-debian > /dev/null
sleep 5

reset_auxclocks
reset_cgroup "realtime.slice"
for INTERFACE in "$@"; do
    reset_driver ${INTERFACE}
    preconfigure_interface ${INTERFACE}
done

# Display a summary of the interface link status
ip -br link

exit 0
