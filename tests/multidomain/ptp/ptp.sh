#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
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


LINUXPTP="${HOME}/devel/demo/ett26/src/linuxptp/"
PTP4L="${LINUXPTP}/ptp4l"
PHC2SYS="${LINUXPTP}/phc2sys"
PHC_CTL="${LINUXPTP}/phc_ctl"

CHRONY="${HOME}/devel/demo/ett26/src/chrony/"
CHRONYD="${CHRONY}/chronyd"

RTCTB="${HOME}/devel/demo/ett26/src/RTC-Testbench/tests/multidomain/"
CONFIGS="${RTCTB}/ptp/configs/"


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

	# E.g. ptp0 for PHC 0
#	PTP_DEVICE="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/)"
	IDXS=$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed 's/ptp//g')
	FIRST_IDX=$(echo ${IDXS} | cut -d' ' -f1)

	# Return the index
	echo "${FIRST_IDX}"
}


function configuration_template () {
	ROLE="$1"

	if [[ "${ROLE}" == "master" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_CMLDS_domain_master.cfg"
	elif [[ "${ROLE}" == "slave" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_CMLDS_domain_slave.cfg"
	elif [[ "${ROLE}" == "bmca" ]]; then
		TEMPLATE="${CONFIGS}/gPTP_CMLDS_domain_BMCA.cfg"
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

	# Run PTP instance
	AFFINITY="6"
	RTPRIO="60"
        sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
	${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m | sudo tee /var/log/ptp4l-${INTERFACE}-cmlds-${ROLE}.log
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
	TEMPLATE="$(configuration_template ${ROLE})"
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
	AFFINITY="6"
	RTPRIO="70"
        sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
	${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m | sudo tee /var/log/ptp4l-${INTERFACE}-gt-${ROLE}.log
}


function run_wc () {
	INTERFACE="$1"
	ROLE="$2"

	PHC_INDEX="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')"
	DOMAIN=1
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX} ${ROLE})"

	# Adjust default LinuxPTP config files
	# Comment out utc_offset as it is the WC
	TEMPLATE="$(configuration_template ${ROLE})"
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
	AFFINITY="6"
	RTPRIO="80"
        sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
	${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m | sudo tee /var/log/ptp4l-${INTERFACE}-wc-${ROLE}.log

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
	AFFINITY="6"
	RTPRIO="90"
	sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
	${PHC2SYS} ${PHC2SYS_ARGS}
}


function run_phc2gt () {
	INTERFACE="$1"

	# chronyd currently lacks the ability to load new PHC refclocks on the
	# fly. We implement a workaround where, if the file exists, we only
	# append the line with the new PHC, and then restart chronyd
	#
	# The companion reset.sh script will delete the chronyd configuration
	# file in /tmp
	#
	# It is *very* fragile, but allows to add NICs incrementally

	PHC_INDEX=$(first_virtual_phc_index ${INTERFACE})
	if [[ -f /tmp/chronyd.conf ]]; then
		sudo pkill -KILL --exact chronyd
		sleep 1
		cat <<EOF >> /tmp/chronyd.conf
refclock PHC /dev/ptp${PHC_INDEX} offset -37 poll 0 refid PHC${PHC_INDEX}
EOF
	else
		cat <<EOF > /tmp/chronyd.conf
port 0
makestep 1.0 -1
refclock PHC /dev/ptp${PHC_INDEX} offset -37 poll 0 refid PHC${PHC_INDEX}
EOF
	fi

	sudo ${CHRONYD} -d -f /tmp/chronyd.conf
}


function run_wc2phc () {
	INTERFACE="$1"
	echo "In this demo each NIC in the master node is an independent WC"
}


function run_phc2wc () {
	INTERFACE="$1"
	ROLE="$2"

	CLOCK_AUX_IDX=$(first_hardware_phc_index ${INTERFACE})
	CLOCK="CLOCK_AUX${CLOCK_AUX_IDX})"
	echo 0 | sudo tee /sys/kernel/time/aux_clocks/${CLOCK_AUX_IDX}/aux_clock_enable > /dev/null
	echo 1 | sudo tee /sys/kernel/time/aux_clocks/${CLOCK_AUX_IDX}/aux_clock_enable > /dev/null

	PHC_INDEX="$(ls -1 /sys/class/net/${INTERFACE}/device/ptp/ | xargs basename --multiple | sed '3,$d' | sed 's/ptp//g')"
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	DOMAIN=1
	TRANSPORT_SPECIFIC="1"
	# /var/run/ptp4lro-master-wc-enp2s0
	UDS_ADDRESS="/var/run/ptp4lro-${ROLE}-wc-${INTERFACE}"

	PHC2SYS_ARGS="-s ${PTP_DEVICE} -c ${CLOCK} -n ${DOMAIN} -z ${UDS_ADDRESS} --transportSpecific=${TRANSPORT_SPECIFIC} -m -w "
	AFFINITY="6"
	RTPRIO="90"
	sudo systemd-run --scope --slice=realtime.slice chrt -f ${RTPRIO} taskset -c ${AFFINITY} \
	${PHC2SYS} ${PHC2SYS_ARGS}
}

