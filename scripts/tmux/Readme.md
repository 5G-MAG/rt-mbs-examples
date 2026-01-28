# Description

This folder contains scripts for the tmux](https://github.com/tmux/tmux)  is a terminal multiplexer.

## Usage

### Starting

In general, to use the tmux scripts, run the following command:

```bash
bash ./<script-name>.sh
```

### Stopping

In general, to stop the tmux session started by the scripts, attach to the tmux session and stop processes. In the tmux
session, press `Ctrl+b` followed by `d` to detach from the session. Then, to kill the tmux session press `Ctrl-b` and
then type `kill-session` and hit Enter.

As an alternative kill the tmux session from a normal session with `tmux kill-session -t <session-name>`. For instance:
`tmux kill-session -t mbsf-tutorial`.

## Scripts

In the following the different scripts available are described.

### MBSF Tutorial Startup script

The `mbs-function-tutorial-startup.sh` script starts the tmux session for
the [MBSF Tutorial](https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html).
It makes it easier to start all the required processes required for execution of the tutorial. Namely, it starts the
following components:
This replaces the manual steps described in
the [Prerequisites](https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbsf.html#prerequisites)
step of the tutorial.

* The NRF, SCP, MB-SMF, MB-UPF, MB-AMF and UDM Network Functions of
  the [Open5GS core](https://github.com/5G-MAG/open5gs)
* The [MBSTF](https://github.com/5G-MAG/rt-mbs-transport-function)
* The [MBSF](https://github.com/5G-MAG/rt-mbs-function)

#### Usage

##### Starting the MBSF Tutorial tmux session

1. Open `mbs-function-tutorial-startup.sh` and set the URL to your Open5GS folder in the `BASE_DIR` variable.
2. Copy your `local-mbsf.yaml` MBSF configuration file to the path defined in `BASE_DIR`.
3. Run `bash ./mbs-function-tutorial-startup.sh` to start the tmux session with all the required components.
4. You can navigate between the different panes using `Ctrl+b` followed by the arrow keys or by typing the concrete
   number of the pane you want to switch to. Navigate to the `UPF`, `MBSTF` and `MBSF` panes and enter the `sudo` password.
5. Now all processes should be running. You can continue using the components now. 

##### Stopping the MBSF Tutorial tmux session

In a normal shell run `tmux kill-session -t mbsf-tutorial`.
