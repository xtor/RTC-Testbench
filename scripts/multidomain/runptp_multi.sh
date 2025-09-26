#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(C) 2025 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Utility bash functions to set up multiple time domains with LinuxPTP and the
# Intel i226 network controller.
#
# It requires LinuxPTP with AS-2020 support. Another convenience script and
# minor patches are provided to compile it.
# FIXME: check if the patches included are alredy committed
#
# It offers two functions:
#
# run_ptp4l_multidomain      - Sets up vclocks and ptp4l configs, calls ptp4l
# run_ptp4l_multidomain_tmux - As above but in different tmux panes


# FIXME: make the interface a parameter
INTERFACE="enp171s0"

# Paths in case a custom compiled version of ptp4l is used
PTP4L="${HOME}/devel/linuxptp/ptp4l"
CONFIG="${HOME}/devel/linuxptp/configs/gPTP.cfg"

CONFIG_CMLDS="/tmp/cmlds.cfg"
CONFIG_DOM0="/tmp/domain-0.cfg"
CONFIG_DOM1="/tmp/domain-1.cfg"


# FIXME This should be integrated with the remaining RTC TB scripts and
# libraries
function cleanup () {

	sudo pkill --full ptp4l

	# Disable EEE
	sudo ethtool --set-eee ${INTERFACE} eee off

	sudo ip link set ${INTERFACE} up

	sleep 5

}


# FIXME: provide the number of vclocks to set up as a parameter
function setup_vclocks {

	INTERFACE="$1"

	# E.g. ptp0 for PHC 0
	PTP_NAME="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"

	# Delete any previously created vclocks
	echo 0 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/n_vclocks > /dev/null

	# Check if we can support at least 4 vclocks
	MAX_VCLOCKS="/sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/max_vclocks"
	# FIXME exit if we do not support the requested number (e.g. 4 vclocks)

	# Setup 4 vclocks
	# FIXME: provide as a parameter
	echo 4 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/n_vclocks > /dev/null

	# Retrieve the first two vclocks
	VCLOCKS=$(ls -1d /sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/ptp? | xargs basename --multiple | sed '3,$d')
	# FIXME: check that the vclocks have been created and which are their device files
}


function generate_cmlds_config {

	PHC_INDEX="$1"
	CLOCK_IDENTITY="$2"

	CONFIG_PATH="/tmp/cmlds.cfg"

	cat << EOF > ${CONFIG_PATH}
#
# Common Mean Link Delay Service (CMLDS) example configuration,
# containing those attributes which differ from the defaults.
# See the file default.cfg for the complete list of available options.
#
[global]
# Set this for CMLDS regardless of actual port roles on this node
clientOnly			1
clockIdentity			${CLOCK_IDENTITY}
free_running			1
ignore_transport_specific	1
transportSpecific		2
uds_address			/var/run/cmlds_server
delay_mechanism			P2P

allowedLostResponses		9

assume_two_step			1
min_neighbor_prop_delay		-20000000
neighborPropDelayThresh		800
network_transport		L2

phc_index			${PHC_INDEX}
EOF
}


function generate_domain_config {

	PHC_INDEX="$1"
	CLOCK_IDENTITY="$2"
	DOMAIN_INDEX="$3"

	CONFIG_PATH="/tmp/domain-${DOMAIN_INDEX}.cfg"

	# Start with the default 802.1AS configuration
	cp ${CONFIG} ${CONFIG_PATH}

	# Comment-out options
	sed -i 's/\(^neighborPropDelayThresh[^$]*\)$/#\1/' ${CONFIG_PATH}
	sed -i 's/\(^min_neighbor_prop_delay[^$]*\)$/#\1/' ${CONFIG_PATH}
	# Update delay_mechanism from P2P to COMMON_P2P
	sed -i 's/\(^delay_mechanism[ \t]*\)P2P/\1COMMON_P2P/' ${CONFIG_PATH}
	# FIXME add comment above the modified COMMON_P2P line

	cat << EOF >> ${CONFIG_PATH}
cmlds.client_address	/var/run/cmlds-client-${DOMAIN_INDEX}
cmlds.server_address	/var/run/cmlds_server
uds_address		/var/run/cmlds-domain-${DOMAIN_INDEX}

domainNumber		${DOMAIN_INDEX}
clockIdentity		${CLOCK_IDENTITY}
phc_index		${PHC_INDEX}
EOF
}


function setup_ptp4l_configs {

	INTERFACE="$1"

	# E.g. ptp0 for PHC 0
	PTP_NAME="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"

	# Retrieve the first two vclocks
	VCLOCK_IDXS=$(ls -1d /sys/class/net/${INTERFACE}/device/ptp/${PTP_NAME}/ptp? | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')
	# FIXME: check that the vclocks have been created and which are their device files

	# Associate domain 0 to the first index, and domain 1 to the second index
	DOMAIN0_VPHC_IDX=$(echo ${VCLOCK_IDXS} | cut -d' ' -f1)
	DOMAIN1_VPHC_IDX=$(echo ${VCLOCK_IDXS} | cut -d' ' -f2)

	# Build the clock identities using the MAC address and the domain
	FIRST_CHUNK=$(cut -d':' -f1-3 /sys/class/net/${INTERFACE}/address | tr -d ':')
	SECOND_CHUNK=$(cut -d':' -f4-5 /sys/class/net/${INTERFACE}/address | tr -d ':')
	THIRD_CHUNK=$(cut -d':' -f6 /sys/class/net/${INTERFACE}/address | tr -d ':')
	DOMAIN0_CLOCK_IDENTITY="${FIRST_CHUNK}.${SECOND_CHUNK}.${THIRD_CHUNK}$(printf %.4x 0)"
	DOMAIN1_CLOCK_IDENTITY="${FIRST_CHUNK}.${SECOND_CHUNK}.${THIRD_CHUNK}$(printf %.4x 1)"

	# Generate the configurations for the CMLDS
	generate_cmlds_config ${DOMAIN0_VPHC_IDX} ${DOMAIN0_CLOCK_IDENTITY}
	generate_domain_config ${DOMAIN0_VPHC_IDX} ${DOMAIN0_CLOCK_IDENTITY} 0
	generate_domain_config ${DOMAIN1_VPHC_IDX} ${DOMAIN1_CLOCK_IDENTITY} 1
}


function setup () {

	INTERFACE="$1"

	setup_vclocks ${INTERFACE}
	setup_ptp4l_configs ${INTERFACE}

}


function run_ptp4l_multidomain_tmux () {

	cleanup
	setup ${INTERFACE}

	# If we are already in a tmux session, detach from it first
	if [ "$TERM_PROGRAM" = tmux ]; then
		tmux detach-client
	fi

	tmux has-session -t multidomain
	# If the session does not exist, create it
	if [ $? != 0 ]; then

		tmux new-session -d -s multidomain
		tmux rename-window 'AS-2020 Multidomain'

		tmux set -g pane-border-status bottom

		tmux select-window -t multidomain:0
		tmux select-pane -t 0 -T "ptp4l CMLDS"
		tmux split-window -v
		tmux select-pane -t 1 -T "ptp4l Domain 0"
		tmux split-window -v
		tmux select-pane -t 2 -T "ptp4l Domain 1"

		tmux send -t 0 "sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_CMLDS}" 'C-m'
		tmux send -t 1 "sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_DOM0}" 'C-m'
		tmux send -t 2 "sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_DOM1}" 'C-m'

		tmux select-pane -t 0

	fi

	tmux -2 attach-session -t multidomain

}


function run_ptp4l_multidomain () {

	cleanup
	setup ${INTERFACE}

	sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_CMLDS}
	sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_DOM0}
	sudo ${PTP4L} -i ${INTERFACE} -m -f ${CONFIG_DOM1}

}
