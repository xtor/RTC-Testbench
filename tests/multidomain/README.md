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

### Step 1: Set up time synchronization

Run the helper ptp-tmux.sh on both nodes to create a set of tmux panes for
managing the bring-up.

On the mirror node:
```
./ptp-tmux.sh enp2s0 mirror
```

On the reference node:
```
./ptp-tmux.sh enp2s0 reference
```

This will trigger immediately the cleanup of stale processes and the reset of
the interfaces included in the test.

After the reset, a CMLDS instance will be started automatically.

The CMLDS instance just measures peer delay and does not have master or
follower roles. Wait for the CMLDS instance to settle, and then start the
Global Time instance on both sides:

On the mirror node:
```
# Start the Global Time domain master
run_gt enp2s0 master
```

On the reference node:
```
# Start the Global Time domain slave
run_gt enp2s0 slave
```

Wait for the Global Time instance to settle, and then start the Working Clock
instance on both sides:

On the mirror node:
```
# Start the Working Clock domain master
run_wc enp2s0 master
```

On the reference node:
```
# Start the Working Clock domain slave
run_wc enp2s0 slave
```

The Global Time instance must run with predefined roles in order to correctly
integrate with the time synchronization pieces at the host level.

Once the Global Time and Working Clock domains are synchronizing, start the
host time synchronization on both ends.

On the mirror node, the Global Time domain masters' PHC will be updated based
on the system time:
```
# Synchronize the system time to the Global Time
run_gt2phc enp2s0 master
```

On the reference node, multiple Global Time sources across the PHCs of the
different controllers will be used to update the system time:
```
# Synchronize the system time to the Global Time
run_phc2gt enp2s0
```

Finally, synchronize the aux clock corresponding to each network controller,
to the Working Clock domain values hold in the respective PHCs.

On the mirror node:
```
# Synchronize CLOCK_AUXn to the Working Clock
run_phc2wc enp2s0 master
```

On the reference node:
```
# Synchronize CLOCK_AUXn to the Working Clock
run_phc2wc enp2s0 slave
```

The specific CLOCK_AUXn is selected based on a value of n corresponding to
the index of the physical PTP device under /dev/ptpn. The helper functions
calculate this value and only enable the required CLOCK_AUXn in order to avoid
performance issues.


### Step 2: Start the RTC TB

Run the helper rtctb-tmux.sh on both nodes to create a set of tmux panes for
managing the bring-up.

On the mirror node:
```
./rtctb-tmux.sh enp2s0 mirror
```

On the reference node:
```
./rtctb-tmux.sh enp2s0 reference
```

Now start the RTC TB as usual.

On the mirror node:
```
sudo ./mirror.sh
```

On the reference node:
```
sudo ./ref.sh
```
