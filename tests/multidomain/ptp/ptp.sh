#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(C) 2026 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
# 
# Usage:
# source ptp.sh && run_cmlds <INTERFACE> <PHC_INDEX>
# source ptp.sh && run_gt <INTERFACE> <PHC_INDEX>
# source ptp.sh && run_wc <INTERFACE> <PHC_INDEX>
#
#  Provides helper bash functions to set up one Global Time and one Working
#  Clock using the IEEE 802.1AS-2020 profile and LinuxPTP.
#
#  TODO: do not pass index as parameter but use 1st physical and 1st virtual
#


LINUXPTP="${HOME}/devel/demo/ett26/src/linuxptp/"
PTP4L="${LINUXPTP}/ptp4l"
PHC_CTL="${LINUXPTP}/phc_ctl"
CONFIGS="${LINUXPTP}/configs/"


function clock_identity () {

	INTERFACE="$1"
	# FIXME use the domain instead
	PHC_INDEX="$2"

	# Build the clock identities using the MAC address and the domain
	FIRST_CHUNK=$(cut -d':' -f1-3 /sys/class/net/${INTERFACE}/address | tr -d ':')
	SECOND_CHUNK=$(cut -d':' -f4-5 /sys/class/net/${INTERFACE}/address | tr -d ':')
	THIRD_CHUNK=$(cut -d':' -f6 /sys/class/net/${INTERFACE}/address | tr -d ':')
	CLOCK_IDENTITY="${FIRST_CHUNK}.${SECOND_CHUNK}.${THIRD_CHUNK}$(printf %.4x ${PHC_INDEX})"

	echo "${CLOCK_IDENTITY}"

}


function run_cmlds () {
	INTERFACE="$1"
	PHC_INDEX="$2"

	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX})"

	PTP4L_CONFIG="/tmp/ptp4l-cmlds-${INTERFACE}.cfg"

	# XXX Executing here now, but code should probably go into reset.sh
	# Set the PHC to 0.0
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	sudo ${PHC_CTL} ${PTP_DEVICE} set 0.0
	sleep 2

	# Create two vclocks
	echo 0 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/ptp0/n_vclocks > /dev/null
	echo 2 | sudo tee /sys/class/net/${INTERFACE}/device/ptp/ptp0/n_vclocks > /dev/null
	sleep 2

	echo "Debug"
	sudo ${PHC_CTL} /dev/ptp0 get
	sudo ${PHC_CTL} /dev/ptp2 get
	sudo ${PHC_CTL} /dev/ptp3 get

	# Adjust default LinuxPTP config files
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(uds_address[[:space:]]*\/var\/run\/cmlds_server\)/\1-${INTERFACE}/" \
            ${CONFIGS}/gPTP_CMLDS_server.cfg > ${PTP4L_CONFIG}

	# Run PTP instance
	sudo ${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m
}


function run_gt () {
	INTERFACE="$1"
	PHC_INDEX="$2"


	# Set the PHC to the system time
	PTP_DEVICE="/dev/ptp${PHC_INDEX}"
	sudo ${PHC_CTL} ${PTP_DEVICE} set
	sleep 2

	echo "Debug"
	sudo ${PHC_CTL} /dev/ptp0 get
	sudo ${PHC_CTL} /dev/ptp2 get
	sudo ${PHC_CTL} /dev/ptp3 get

	# Adjust default LinuxPTP config files
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX})"
	PTP4L_CONFIG="/tmp/ptp4l-gt-${INTERFACE}.cfg"
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(cmlds.server_address[[:space:]]*\/var\/run\/cmlds_server\)/\1-${INTERFACE}/" \
	    -e "s/\(cmlds.client_address[[:space:]]*\/var\/run\/cmlds-client-0\)/\1-${INTERFACE}/" \
	    -e "s/\(uds_address[[:space:]]*\/var\/run\/cmlds-domain-0\)/\1-${INTERFACE}/" \
            ${CONFIGS}/gPTP_CMLDS_domain0.cfg > ${PTP4L_CONFIG}

	# Run PTP instance
	sudo ${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m
}


function run_wc () {
	INTERFACE="$1"
	PHC_INDEX="$2"



	echo "Debug"
	sudo ${PHC_CTL} /dev/ptp0 get
	sudo ${PHC_CTL} /dev/ptp2 get
	sudo ${PHC_CTL} /dev/ptp3 get

	# Adjust default LinuxPTP config files
	CLOCK_IDENTITY="$(clock_identity ${INTERFACE} ${PHC_INDEX})"
	PTP4L_CONFIG="/tmp/ptp4l-wc-${INTERFACE}.cfg"
        sed -e "s/\(phc_index[[:space:]]*\)[^ ]*/\1${PHC_INDEX}/" \
	    -e "s/\(clockIdentity[[:space:]]*\)[^ ]*/\1${CLOCK_IDENTITY}/" \
	    -e "s/\(cmlds.server_address[[:space:]]*\/var\/run\/cmlds_server\)/\1-${INTERFACE}/" \
	    -e "s/\(cmlds.client_address[[:space:]]*\/var\/run\/cmlds-client-1\)/\1-${INTERFACE}/" \
	    -e "s/\(uds_address[[:space:]]*\/var\/run\/cmlds-domain-1\)/\1-${INTERFACE}/" \
            ${CONFIGS}/gPTP_CMLDS_domain1.cfg > ${PTP4L_CONFIG}

	# Run PTP instance
	sudo ${PTP4L} -i ${INTERFACE} -f ${PTP4L_CONFIG} -m
}
