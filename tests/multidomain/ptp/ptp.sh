#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Usage:
# source ptp.sh && run_cmlds <INTERFACE>
# source ptp.sh && run_gt <INTERFACE> [bmca|master|slave]
# source ptp.sh && run_wc <INTERFACE> [bmca|master|slave]
#
#  Provides helper bash functions to set up one Global Time and one Working
#  Clock using the IEEE 802.1AS-2020 profile and LinuxPTP.
#


LINUXPTP="./linuxptp/"
PTP4L="${LINUXPTP}/ptp4l"
PHC2SYS="${LINUXPTP}/phc2sys"
PHC_CTL="${LINUXPTP}/phc_ctl"
PMC="${LINUXPTP}/pmc"

CHRONY="./chrony/"
CHRONYD="${CHRONY}/chronyd"
CHRONYC="${CHRONY}/chronyc"

RTCTB="${HOME}/devel/demo/ett26/src/RTC-Testbench/tests/multidomain/"
CONFIGS="${RTCTB}/ptp/configs/"


function run_rt_pid () {
	local AFFINITY="$1"
	local RTPRIO="$2"
	local PID="$3"

	echo ${PID} | sudo tee /sys/fs/cgroup/realtime.slice/cgroup.procs
	sudo taskset -p --cpu-list ${AFFINITY} ${PID}
	sudo chrt -f -p ${RTPRIO} ${PID}
}


function run_rt_cmd () {
	local AFFINITY="$1"
	local RTPRIO="$2"
	local COMMAND="$3"

        sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} ${COMMAND}
}


function affinity_for_interface () {
	local INTERFACE="$1"

	if [[ "${INTERFACE}" == "enp1s0" ]]; then
		AFFINITY="4"
	elif [[ "${INTERFACE}" == "enp2s0" ]]; then
		AFFINITY="5"
	else
		echo "Interface ${INTERFACE} not tunable. Aborting..."
		return
	fi

	echo ${AFFINITY}
}

function tune_timestamping () {
	INTERFACE="$1"

	AFFINITY=$(affinity_for_interface ${INTERFACE})


	# Set affinity and increase the priority of the timestamping interrupt handler
	IRQ_TS=$(ls -1 /sys/class/net/${INTERFACE}/device/msi_irqs/ | head -1)
	echo ${AFFINITY} | sudo tee /proc/irq/${IRQ_TS}/smp_affinity_list
	IRQ_TS_PID=$(pgrep -a "irq/${IRQ_TS}-${INTERFACE}" | cut -f1 -d' ')
	# The affinity will automatically match the one set for the IRQ
	RTPRIO="97"
	sudo chrt --fifo -p ${RTPRIO} ${IRQ_TS_PID}

	# Set the affinity of the remaining interrupt handlers
	OTHER_IRQS=$(ls -1 /sys/class/net/${INTERFACE}/device/msi_irqs/ | sed -n '2,$p')
	for IRQ in ${OTHER_IRQS}; do
		echo "0-3" | sudo tee /proc/irq/${IRQ}/smp_affinity_list
	done

	# Queue 1 is used for Network Control, affinitize its interrupt to the same core
	# So the NAPI thread runs with the interrupt
	IRQ_NC="$(cat /proc/interrupts | grep ${INTERFACE}-TxRx-1 | cut -f1 -d':' | sed 's/ //g')"
	echo ${AFFINITY} | sudo tee /proc/irq/${IRQ_NC}/smp_affinity_list

	# We mapped Network Control to queue 1
	NC_PID=$(pgrep -f "irq/${IRQ_NC}-${INTERFACE}-TxRx-1" | cut -f1 -d' ')
	# The affinity will automatically match the one set for the IRQ
	RTPRIO="95"
	sudo chrt --fifo -p ${RTPRIO} ${NC_PID}

	# Affinitize the NAPI instance for Queue 1 to the same core
	RTPRIO="93"
	NAPI_ID=$(sudo ../../build/napictl -i ${INTERFACE} -q 1 -v | grep 'Tx NAPI' | cut -d':' -f2 | sed 's/ //g')
	NAPI_PID=$(pgrep -a "napi/${INTERFACE}-${NAPI_ID}" | cut -f1 -d' ')
	run_rt_pid ${AFFINITY} ${RTPRIO} ${NAPI_PID}

}


function clock_identity () {

	INTERFACE="$1"
	PHC_INDEX="$2"
	ROLE="$3"

	if [[ "${ROLE}" == "cmlds" ]]; then
		ROLE_CODE=0
	elif [[ "${ROLE}" == "master" ]]; then
		ROLE_CODE=1
	elif [[ "${ROLE}" == "slave" ]]; then
		ROLE_CODE=2
	elif [[ "${ROLE}" == "bmca" ]]; then
		ROLE_CODE=3
	else
		echo "Unknown ${ROLE} role. Aborting..."
		return
	fi


	# Build the clock identities using the MAC address, the index and the role
	FIRST_CHUNK=$(cut -d':' -f1-3 /sys/class/net/${INTERFACE}/address | tr -d ':')
	SECOND_CHUNK=$(cut -d':' -f4-5 /sys/class/net/${INTERFACE}/address | tr -d ':')
	THIRD_CHUNK=$(cut -d':' -f6 /sys/class/net/${INTERFACE}/address | tr -d ':')
	FOURTH_CHUNK="$(printf %.2x ${PHC_INDEX})$(printf %.2x ${ROLE_CODE})"
	CLOCK_IDENTITY="${FIRST_CHUNK}.${SECOND_CHUNK}.${THIRD_CHUNK}${FOURTH_CHUNK}"

	echo "${CLOCK_IDENTITY}"

}


function first_virtual_phc_index () {
	INTERFACE="$1"

	# E.g. ptp0 for PHC 0
	PTP_DEVICE="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"

	# Retrieve the vclocks for PTP_NAME
	VCLOCK_IDXS=$(ls -1d /sys/class/ptp/${PTP_DEVICE}/ptp* | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')
	FIRST_VCLOCK_IDX=$(echo ${VCLOCK_IDXS} | cut -d' ' -f1)

	# Return the index
	echo "${FIRST_VCLOCK_IDX}"
}


function first_hardware_phc_index () {
	INTERFACE="$1"

	IDXS=$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed 's/ptp//g')
	FIRST_IDX=$(echo ${IDXS} | cut -d' ' -f1)

	# Return the index
	echo "${FIRST_IDX}"
}


function configuration_template () {
	ROLE="$1"
	TYPE="$2"

	if [[ "${ROLE}" == "master" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_${TYPE}_domain_master.cfg"
	elif [[ "${ROLE}" == "slave" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_${TYPE}_domain_slave.cfg"
	elif [[ "${ROLE}" == "bmca" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_${TYPE}_domain_BMCA.cfg"
	else
		echo "Unknown ${ROLE} role. Aborting..."
		return
	fi

	echo "${TEMPLATE}"
}


function run_cmlds () {
	INTERFACE="$1"

	ROLE="cmlds"

	# Create a single vClock
	# E.g. ptp0 for PHC 0
	PTP_DEVICE="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"
	echo 0 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/${PTP_DEVICE}/n_vclocks > /dev/null
	echo 1 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/${PTP_DEVICE}/n_vclocks > /dev/null
	sleep 2

	PHC_INDEX=$(first_virtual_phc_index ${INTERFACE})
	DOMAIN=0
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX} ${ROLE})"

	# Adjust default LinuxPTP config files
        TEMPLATE="${CONFIGS}/gPTP_CMLDS_server.cfg"
	PTP4L_CONFIG="/tmp/ptp4l-cmlds-${INTERFACE}.cfg"
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(uds_address[[:space:]]*\/var\/run\/cmlds_server\)/\1-${INTERFACE}/" \
	    -e "s/\(message_tag[[:space:]]*[^ ]*\)/\1-${INTERFACE}/" \
            ${TEMPLATE} > ${PTP4L_CONFIG}

	AFFINITY=$(affinity_for_interface ${INTERFACE})

	# Tune the PTP worker for the vclock
	RTPRIO="91"
	PTP_WORKER_PID=$(pgrep -a "ptp${PHC_INDEX}" | cut -f1 -d' ')
	run_rt_pid ${AFFINITY} ${RTPRIO} ${PTP_WORKER_PID}

	# Run PTP instance
	RTPRIO="70"
	COMMAND="${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m"
	run_rt_cmd ${AFFINITY} ${RTPRIO} "${COMMAND}" | sudo tee /var/log/ptp4l-${INTERFACE}-${ROLE}.log
}


function run_gt () {
	INTERFACE="$1"
	ROLE="$2"

	PHC_INDEX=$(first_virtual_phc_index ${INTERFACE})
	DOMAIN=0
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX} ${ROLE})"

	# Set the PHC to the system time once
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	sudo ${PHC_CTL} ${PTP_DEVICE} set
	sleep 2

	# Adjust default LinuxPTP config files
	TEMPLATE="$(configuration_template ${ROLE} CMLDS)"
	PTP4L_CONFIG="/tmp/ptp4l-gt-${ROLE}-${INTERFACE}.cfg"
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
            -e "s/\(^domainNumber[[:space:]]*\)[^ ]*/\1${DOMAIN}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(cmlds.server_address[[:space:]]*[^ ]*\)/\1-${INTERFACE}/" \
	    -e "s/\(cmlds.client_address[[:space:]]*[^ ]*\)/\1-gt-${INTERFACE}/" \
	    -e "s/\(uds_address[[:space:]]*[^ ]*\)/\1-gt-${INTERFACE}/" \
	    -e "s/\(uds_ro_address[[:space:]]*[^ ]*\)/\1-gt-${INTERFACE}/" \
	    -e "s/\(message_tag[[:space:]]*[^ ]*\)/\1-${INTERFACE}-gt/" \
            ${TEMPLATE} > ${PTP4L_CONFIG}

	# Run PTP instance
	AFFINITY=$(affinity_for_interface ${INTERFACE})
	RTPRIO="75"
	COMMAND="${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m"
	run_rt_cmd ${AFFINITY} ${RTPRIO} "${COMMAND}" | sudo tee /var/log/ptp4l-${INTERFACE}-gt-${ROLE}.log
}


function run_wc () {
	INTERFACE="$1"
	ROLE="$2"

	PHC_INDEX="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')"
	DOMAIN=1
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX} ${ROLE})"

	# Adjust default LinuxPTP config files
	# Comment out utc_offset as it is the WC
	TEMPLATE="$(configuration_template ${ROLE} CMLDS)"
	PTP4L_CONFIG="/tmp/ptp4l-wc-${ROLE}-${INTERFACE}.cfg"
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
            -e "s/\(^domainNumber[[:space:]]*\)[^ ]*/\1${DOMAIN}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(cmlds.server_address[[:space:]]*[^ ]*\)/\1-${INTERFACE}/" \
	    -e "s/\(cmlds.client_address[[:space:]]*[^ ]*\)/\1-wc-${INTERFACE}/" \
	    -e "s/\(uds_address[[:space:]]*[^ ]*\)/\1-wc-${INTERFACE}/" \
	    -e "s/\(uds_ro_address[[:space:]]*[^ ]*\)/\1-wc-${INTERFACE}/" \
	    -e "s/\(utc_offset[[:space:]]*[^ ]*\)/#\1/" \
	    -e "s/\(message_tag[[:space:]]*[^ ]*\)/\1-${INTERFACE}-wc/" \
            ${TEMPLATE} > ${PTP4L_CONFIG}

	# Run PTP instance
	AFFINITY=$(affinity_for_interface ${INTERFACE})
	RTPRIO="85"
	COMMAND="${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m"
	run_rt_cmd ${AFFINITY} ${RTPRIO} "${COMMAND}" | sudo tee /var/log/ptp4l-${INTERFACE}-gt-${ROLE}.log &

	# Set PTP timescale to 0
	if [[ "${ROLE}" == "master" ]]; then
		# Let the UDS be created
		sleep 2
		# XXX fix this, read values first, then set ptp_timescale to 0
		# instead of overwriting
		sudo ${PMC} -u -d ${DOMAIN} -s /var/run/ptp4l-master-wc-${INTERFACE} -t 1 -b 0 "SET GRANDMASTER_SETTINGS_NP clockClass 248 clockAccuracy 0xfe offsetScaledLogVariance 0xffff currentUtcOffset 37 leap61 0 leap59 0 currentUtcOffsetValid 1 ptpTimescale 0 timeTraceable 0 frequencyTraceable 0 timeSource 0xa0"
	fi

	fg
}


function run_gt2phc () {
	INTERFACE="$1"
	ROLE="$2"

	PHC_INDEX=$(first_virtual_phc_index ${INTERFACE})
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	DOMAIN=0
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX} ${ROLE})"
	TRANSPORT_SPECIFIC="1"
	# /var/run/ptp4lro-master-gt-enp2s0
	UDS_ADDRESS="/var/run/ptp4lro-${ROLE}-gt-${INTERFACE}"

	PHC2SYS_ARGS="-s CLOCK_REALTIME -c ${PTP_DEVICE} -n ${DOMAIN} -z ${UDS_ADDRESS} --transportSpecific=${TRANSPORT_SPECIFIC} -m -w "
	AFFINITY=$(affinity_for_interface ${INTERFACE})
	RTPRIO="77"
	COMMAND="${PHC2SYS} ${PHC2SYS_ARGS}"
	run_rt_cmd $AFFINITY $RTPRIO "$COMMAND"
}


function run_phc2gt () {
	INTERFACE="$1"

	# chronyd currently lacks the ability to load new PHC refclocks on the
	# fly. We implement a workaround using the confdir directive. This
	# allows us to add config files per interface dynamically.
	#
	# Unfortunately, we can only reload the configuration by killing the
	# process and starting it again.

	PHC_INDEX=$(first_virtual_phc_index ${INTERFACE})
	if [[ ! -d /tmp/chrony ]]; then
		mkdir -p /tmp/chrony/chrony.d
		cat <<EOF > /tmp/chrony/chrony.conf
# Disable NTP server port
port 0
makestep 1.0 -1
confdir /tmp/chrony/chrony.d
EOF
	fi

	cat <<EOF >> /tmp/chrony/chrony.d/${INTERFACE}.conf
refclock PHC /dev/ptp${PHC_INDEX} offset -37 poll 0 refid PHC${PHC_INDEX}
EOF

	sudo pkill -KILL --exact chronyd
	sleep 0.5

	AFFINITY=$(affinity_for_interface ${INTERFACE})
	RTPRIO="77"
	sudo ${CHRONYD} -f /tmp/chrony/chrony.conf

	sudo watch ${CHRONYC} sources
}


function run_wc2phc () {
	INTERFACE="$1"
	echo "In this demo each NIC in the master node is an independent WC"
}


function run_phc2wc () {
	INTERFACE="$1"
	ROLE="$2"

	CLOCK_AUX_IDX=$(first_hardware_phc_index ${INTERFACE})
	CLOCK="CLOCK_AUX${CLOCK_AUX_IDX}"
	echo 0 | sudo tee /sys/kernel/time/aux_clocks/${CLOCK_AUX_IDX}/aux_clock_enable > /dev/null
	echo 1 | sudo tee /sys/kernel/time/aux_clocks/${CLOCK_AUX_IDX}/aux_clock_enable > /dev/null

	PHC_INDEX="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')"
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	DOMAIN=1
	TRANSPORT_SPECIFIC="1"
	# /var/run/ptp4lro-master-wc-enp2s0
	UDS_ADDRESS="/var/run/ptp4lro-${ROLE}-wc-${INTERFACE}"

	PHC2SYS_ARGS="-s ${PTP_DEVICE} -c ${CLOCK} -n ${DOMAIN} -z ${UDS_ADDRESS} --transportSpecific=${TRANSPORT_SPECIFIC} -m -w "
	AFFINITY=$(affinity_for_interface ${INTERFACE})
	RTPRIO="87"
	COMMAND="${PHC2SYS} ${PHC2SYS_ARGS}"
	run_rt_cmd $AFFINITY $RTPRIO "$COMMAND"
}
