# Description

This folder contains scripts for [tmux](https://github.com/tmux/tmux) an open-source terminal multiplexer that allows
users to manage multiple terminal sessions, windows, and panes from a single screen or terminal window.

# Usage

## Starting

In general, to use the tmux scripts, run the following command:

```bash
bash ./<script-name>.sh
```

## Stopping

In general, to stop the tmux session started by the scripts, attach to the tmux session and stop processes. In the tmux
session, press `Ctrl+b` and then type `:kill-session` and hit Enter.

As an alternative kill the tmux session from a normal session with `tmux kill-session -t <session-name>`. For instance:
`tmux kill-session -t mbsf-tutorial`.

# Scripts

In the following the different scripts available are described.

## MBSF Tutorial Startup script

The `mbs-function-tutorial-startup.sh` script located in `mbs-function-tutorial` starts the tmux session for
the [MBSF Tutorial](https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html).
It makes it easier to start all the required processes required for execution of the tutorial. This replaces the manual
steps described in
the [Prerequisites](https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html#prerequisites)
step of the tutorial. Namely, it starts the following components:

* The `NRF`, `SCP`, `MB-SMF`, `MB-UPF`, `MB-AMF` and `UDM` Network Functions of
  the [Open5GS core](https://github.com/5G-MAG/open5gs)
* The [MBSTF](https://github.com/5G-MAG/rt-mbs-transport-function)
* The [MBSF](https://github.com/5G-MAG/rt-mbs-function)

### Usage

#### Starting the MBSF Tutorial tmux session

1. From the root folder of this project navigate to `scripts/tmux`
2. In `mbs-function-tutorial.sh` adjust the directories of your setup:

   ```
   OPEN5GS_BASE_DIR="/home/fivegmag/Developer/open5gs_mbs/install/bin"
   OPEN5GS_CONFIG_DIR="/home/fivegmag/Developer/open5gs_mbs/install/etc/open5gs"
   MBSTF_BASE_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
   MBSTF_CONFIG_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
   MBSF_BASE_DIR="/home/fivegmag/Developer/rt-mbs-function/build/src/mbsf"
   MBSF_CONFIG_DIR="/home/fivegmag/Developer/rt-mbs-examples/scripts/tmux/mbs-function-tutorial"
   MEDIA_SERVER_DIR="/home/fivegmag/Developer/rt-mbs-examples/express-mock-media-server"
   LOG_DIR="/var/local/log/open5gs"
   ```
3. Optional: Adjust the MBSF configuration located in `local-mbsf.yaml` if needed and the file name in "MBSF|$MBSF_BASE_DIR/open5gs-mbsfd -c $MBSF_CONFIG_DIR/local-mbsf.yaml"`
4. Run `bash ./mbs-function-tutorial.sh` to start the tmux session with all the required components.
5. Now all processes should be running. You can continue using the components now.

#### Stopping the MBSF Tutorial tmux session

In the tmux session, press `Ctrl+b` followed by `:kill-session` and hit Enter.

As an alternative, in a normal shell run `tmux kill-session -t mbsf-tutorial`.

In case there are still Open5GS processes running you can terminate them with
`sudo pkill -TERM -f 'open5gs-(nrfd|scpd|smfd|upfd|amfd|udmd|mbstfd|mbsfd)'`

## MBSTF Tutorial Startup script

The `mbs-transport-function-testing-tutorial.sh` script located in `mbs-transport-function-tutorial` starts
an automated tmux session for MBSTF transport-function API example runs. It makes it easier to start all required
components in one step instead of launching each process manually. Namely, it starts the following components:

* The `NRF`, `SCP`, `SMF`, `UPF` and `AMF` Network Functions of
  the [Open5GS core](https://github.com/5G-MAG/open5gs)
* The [MBSTF](https://github.com/5G-MAG/rt-mbs-transport-function)
* The simple media server located in `express-mock-media-server`

### Usage

#### Starting the MBSTF Tutorial tmux session

1. From the root folder of this project navigate to `scripts/tmux/mbs-transport-function-tutorial`.
2. In `mbs-transport-function-tutorial.sh` adjust the directories of your setup:

   ```
   OPEN5GS_BASE_DIR="/home/fivegmag/Developer/open5gs_mbs/install/bin"
   OPEN5GS_CONFIG_DIR="/home/fivegmag/Developer/open5gs_mbs/install/etc/open5gs"
   MBSTF_BASE_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
   MBSTF_CONFIG_DIR="/home/fivegmag/Developer/rt-mbs-transport-function/build/src/mbstf"
   MEDIA_SERVER_DIR="/home/fivegmag/Developer/rt-mbs-examples/express-mock-media-server"
   LOG_DIR="/var/local/log/open5gs"
   ```
   
4. Run `bash ./mbs-transport-function-tutorial.sh` to start the tmux session with all required components.
5. You can navigate between the different panes using `Ctrl+b` followed by the arrow keys or by typing the concrete number of the pane you want to switch to.

#### Stopping the MBSTF Tutorial tmux session

In the tmux session, press `Ctrl+b` followed by `:kill-session` and hit Enter.

As an alternative, in a normal shell run `tmux kill-session -t mbstf-tutorial`.

In case there are still Open5GS, MBSTF, or MediaServer processes running you can terminate them with
`sudo pkill -TERM -f 'open5gs-(nrfd|scpd|smfd|upfd|amfd)|open5gs-mbstfd|node'`
