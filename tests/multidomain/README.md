# Linux Real-Time Communications Multi-Domain

## Overview

This test configuration deploys several RTC Testbench instances. Each instance
is attached to a different NIC. All the instances across the reference and
mirror nodes:
* Share the same synchronized system time (e.g. CLOCK_TAI)
* Use differentiated working clocks for each reference / mirror pair

Network synchronization:
* Each NIC pair across reference and mirror nodes is synchronized using the gPTP
802.1AS-2020 profile with two time domains.
* Each link synchronizes the Global Time Domain, and a differenciated Working
Clock Domain.
* Each link uses a CMLDS service shared by all the PTP domains on that link

System synchronization:
* The source of the Global Time is a one-off mirror synchronization via NTP
* The Global Time is made available to applications using CLOCK_TAI
* The Working Clocks are made available to applications using aux clocks (e.g.
CLOCK_AUX0, CLOCK_AUX1, and so on)


## Building

### Software Dependencies

As of May 2026, this test requires several patches to the upstream Debian 13
and Linux kernel software baselines.

* Linux kernel 
  * PTP device vclock support
  * Auxiliary clocks support in kernel and headers
  * System call support for the relevant system calls (e.g. clock_nanosleep)
  * https://git.kernel.org/pub/scm/linux/kernel/git/thomas.weissschuh/linux.git/?h=b4/auxclock-nanosleep

* LinuxPTP
  * ptp4l IEEE 802.1AS-2020 Multiple time domains support
  * phc2sys, phc_ctl, etc support for auxiliary clocks
  * `git clone -b staging https://github.com/mlichvar/linuxptp.git`
    * Plus fix for timestamping error on vclock applied to raw.c

The RTC TB scripts contain environment variables to customize the path for the
relevant binaries. After compiling the software above, make sure the paths are
updated in the scripts.

### Hardware Dependencies

This configuration depends on the following configuration in order to offer
end-to-end time synchronization across network and SoC:
* Two Intel Bartlett Lake-S 12P nodes with Time Coordinated Computing support
* Three Intel i226 network controllers on each node, connected back-to-back


## Usage

### Step 1: Set up time synchronization across the network

Run the helper scripts and functions on mirror and reference nodes:
```
# Remove interferring services and stale processes from previous executions
platform/cleanup.sh

# Reset the system and network controller configuration
platform/reset.sh

# Start PTP with multiple time domains, one command per console
# Adjust the interface and the vclock index for the CMLDS and GT instances
source ptp/ptp.sh && run_cmlds enp2s0
source ptp/ptp.sh && run_gt    enp2s0 [master|slave]
source ptp/ptp.sh && run_wc    enp2s0 bmca
```

The CMLDS instance just measures peer delay and does not have master or
follower roles.

The Working Clock instance may run with the BMCA in this example.

The Global Time instance must run with predefined roles in order to correctly
integrate with the time synchronization pieces at the host level.
