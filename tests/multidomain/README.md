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

As of July 2026, this test requires several patches to the upstream Debian 13
and Linux kernel software baselines.

* Linux kernel
  * Features required
    * PTP device vclock support
    * Auxiliary clocks support in kernel and headers
    * Auxiliary clock support for the relevant system calls (e.g. clock_nanosleep)
  * Thomas Weissschuh's auxclock-nanosleep is suggested
    * https://git.kernel.org/pub/scm/linux/kernel/git/thomas.weissschuh/linux.git/?h=b4/auxclock-nanosleep

* LinuxPTP
  * ptp4l IEEE 802.1AS-2020 Multiple time domains support
  * phc2sys, phc_ctl, etc support for auxiliary clocks
  * LinuxPTP's upstream tip is suggested

The RTC TB scripts contain environment variables to customize the path for the
relevant binaries. After compiling the software above, make sure the paths are
updated in the scripts.


### Hardware Dependencies

This configuration depends on the following configuration in order to offer
end-to-end time synchronization across network and SoC:
* Two Intel Bartlett Lake-S 12P nodes with Time Coordinated Computing support
* Three Intel i226 network controllers on each node, connected back-to-back


## Usage


### Step 1: Set up the platform configuration

This step will remove stale processes, reset network drivers and perform other
cleanup and preparation tasks to make sure the initial state is the same.

On the mirror node:
```
./platform-tmux.sh enp1s0 mirror
```

On the reference node:
```
./platform-tmux.sh enp1s0 reference
```


### Step 2: Set up time synchronization

Run the helper ptp-tmux.sh on both nodes to create a set of tmux panes for
managing the bring-up.

On the mirror node:
```
./ptp-tmux.sh enp1s0 mirror
```

On the reference node:
```
./ptp-tmux.sh enp1s0 reference
```

Each pane will be ready to execute a different initialization command. The
suggested order is:
1. CMLDS on mirror
1. CMLDS on reference
1. Global Time domain on mirror (forces master role)
1. Global Time local synchronization on mirror
1. Global Time domain on reference (forces follower role)
1. Global Time local synchronization on reference
1. Working Clock domain on mirror (forces master role)
1. Working Clock local synchronization on mirror
1. Working Clock domain on reference (forces follower role)
1. Working Clock local synchronization on reference

In full detail:

CMLDS:

On the mirror node:
```
run_cmlds enp1s0
```

On the reference node:
```
run_cmlds enp1s0
```

Wait for CMLDS to stabilize, and then start Global Time on both sides:

On the mirror node:
```
# Start the Global Time domain master in its pane
run_gt enp1s0 master
```
```
# Synchronize the system time to the Global Time by running on its pane
run_gt2phc enp1s0 master
```

On the reference node:
```
# Start the Global Time domain slave in its pane
run_gt enp1s0 slave
```

```
# Synchronize the system time to the Global Time by running on its pane
run_phc2gt enp1s0
```

Wait for the Global Time instance to settle, and then start the Working Clock
instance on both sides:

On the mirror node:
```
# Start the Working Clock domain master
run_wc enp1s0 master
```

```
# Synchronize CLOCK_AUXn to the Working Clock
run_phc2wc enp1s0 master
```
The specific CLOCK_AUXn is selected based on a value of n corresponding to
the index of the physical PTP device under /dev/ptpn. The helper functions
calculate this value and only enable the required CLOCK_AUXn in order to avoid
performance issues.

On the reference node:
```
# Synchronize CLOCK_AUXn to the Working Clock
run_phc2wc enp1s0 slave
```

```
# Start the Working Clock domain slave
run_wc enp1s0 slave
```


### Step 3: Start the RTC TB

Run the helper rtctb-tmux.sh on both nodes to create a set of tmux panes for
managing the bring-up.

On the mirror node:
```
./rtctb-tmux.sh enp1s0 mirror crypto
```

On the reference node:
```
./rtctb-tmux.sh enp1s0 reference crypto
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
