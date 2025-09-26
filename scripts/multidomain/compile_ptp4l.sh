#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(C) 2025 Intel Corporation
# Authors:
#   Hector Blanco Alcaine
#
# Clones the upstream github repo for LinuxPTP, applies a few missing AS-2020
# patches and compiles the resulting sources. 
#
# FIXME: check if the patches are already applied in a newer LinuxPTP version


DIR="${HOME}/devel"

mkdir -p ${DIR}
# XXX Be careful with this ;)
rm -rf ${DIR}/linuxptp
git clone https://github.com/richardcochran/linuxptp.git ${DIR}/linuxptp
cp *patch ${DIR}/linuxptp
cd ${DIR}/linuxptp

patch -p1 < 0001-port-Implement-gPTP-capable-TLV-signaling-message-pr.patch
patch -p1 < 0002-port-Implement-asCapableAcrossDomains-and-neighborGp.patch
patch -p1 < 0003-port-Add-neighborGptpCapable-AS2011-backward-compati.patch
patch -p1 < 0001-doc-add-example-for-IEEE-802.1AS-2020-multi-time-dom.patch

make
