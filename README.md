<h1 align="center">MBS Examples</h1>
<p align="center">
  <img src="https://img.shields.io/badge/Status-Under_Development-yellow" alt="Under Development">
  <img src="https://img.shields.io/badge/License-5G--MAG%20Public%20License%20(v1.0)-blue" alt="License">
</p>

## Introduction

3GPP Release 17 brings Multicast–Broadcast Services (MBS) to the 5G System, based on 5G Core and New Radio. MBS allows
the network to select the most suitable among point-to-multipoint (PTM) or point-to-point (PTP) delivery based on
requirements set by either service providers or network operators and/or taking into account concurrent user demand.

Additional information can be found at: https://5g-mag.github.io/Getting-Started/pages/5g-multicast-broadcast-services/

### About the implementation

This repository contains Docker Compose components to deploy several network functions related to MBS.
The detailed usage instructions are available at
the [Getting Started guides](https://5g-mag.github.io/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbs-in-5gc.html).

> [!NOTE]
> Docker images are available for `amd64/x86-64` and `arm64` based systems.

Some of the components are unmodified Open5GS Network Functions, those are marked with the regular Network Function's
name and follow Open5GS' versioning, the latest version available is the `v2.7.2`.

| Network Function | image name          | version |
|------------------|---------------------|---------|
| AUSF             | ghcr.io/5g-mag/ausf | v2.7.2  |
| BSF              | ghcr.io/5g-mag/bsf  | v2.7.2  |
| NRF              | ghcr.io/5g-mag/nrf  | v2.7.2  |
| NSSF             | ghcr.io/5g-mag/nssf | v2.7.2  |
| PCF              | ghcr.io/5g-mag/pcf  | v2.7.2  |
| UDM              | ghcr.io/5g-mag/udm  | v2.7.2  |
| UDR              | ghcr.io/5g-mag/udr  | v2.7.2  |

# Installing Dependencies

Follow the [steps for your distribution](https://docs.docker.com/engine/install/) and install the docker buildx and
docker compose plugins

## Building

> [!NOTE]
> This method uses the `docker-bake.hcl` file and requires `docker-buildx-plugin`

> [!IMPORTANT]
> When building the images, modify the `FIVEG_MAG_MBS_VERSION` and `OPEN5GS_VERSION` variables in the `.env` file to use
> a specific version.

From the top level directory of the repository run:

```bash
  cd rt-mbs-examples
  docker buildx bake
```

## Running

Two different deployments have been created to test this project, `internal` and `external`:
- The `internal` deployment consists of an end-to-end setup consisting of a 5G Core with MBS features, a gNB and a UE. Everything ready to be tested on the *internal* network using only the components deployed.

First modify the `.env` file. Change the `DOCKER_HOST_IP=<your_host_ip_address>` with your machine's IP address, like
this `DOCKER_HOST_IP=192.168.1.2`. This lets the UPF + MB-UPF use your machine's Internet connection to route the
traffic using NAT.

To run the Docker images, select either the `internal` deployment or the `external` deployment and from the top level
directory of the repository:

### Internal Deployment

```bash
# to use the internal deployment
docker compose -f compose-files/internal/docker-compose.yaml --env-file=.env up -d
```

```bash
# to tear down the internal deployment
docker compose -f compose-files/internal/docker-compose.yaml --env-file=.env down
```
### Establishing a 5G-MBS Broadcast session and sending video

To create a 5G-MBS Broadcast session we need to execute the following command

```bash
docker exec -it test_mbs_af_as sendrequest
```
With this command the AF (application function) sends a request to the UPF. 

After sending the request we can put the UE to receive the content in a different terminal with the following command:

```bash
docker exec -it ue_with_mbs receivevideo
```

Then we can start sending the video from the AF:

```bash
docker exec -it test_mbs_af_as sendvideo
```
This will use a sample video that is inside the AF container. If everything works we should see in the terminal executing the UE an ASCII representation of the video.

