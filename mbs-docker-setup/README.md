# 5G MBS System: Docker setup

## About the implementation

This repository contains Docker Compose components to deploy several 5G Core Network Functions (NFs) related to the 5G MBS System.

Detailed usage instructions are available at
the [Getting Started guides](https://5g-mag.github.io/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbs-in-5gc.html).

> [!NOTE]
> Docker images are available for `amd64/x86-64`- and `arm64`-based systems.

### 5G Core

Some of the components are unmodified [Open5GS](https://github.com/5G-MAG/open5gs) Network Functions; these are marked with the regular Network Function's name and follow Open5GS versioning.

| Network Function | Image name          | Version |
|------------------|---------------------|---------|
| AUSF             | ghcr.io/5g-mag/ausf | v2.7.7  |
| BSF              | ghcr.io/5g-mag/bsf  | v2.7.7  |
| NRF              | ghcr.io/5g-mag/nrf  | v2.7.7  |
| NSSF             | ghcr.io/5g-mag/nssf | v2.7.7  |
| PCF              | ghcr.io/5g-mag/pcf  | v2.7.7  |
| UDM              | ghcr.io/5g-mag/udm  | v2.7.7  |
| UDR              | ghcr.io/5g-mag/udr  | v2.7.7  |

The following Open5GS NFs are customised by 5G-MAG contributors to support MBS. These follow 5G-MAG versioning.

| Network Function   | Image name                    | Version | Remarks                                  |
|--------------------|-------------------------------|---------| ---------------------------------------- |
| NRF (5G-MAG)       | ghcr.io/5g-mag/nrf_5gmag      | 0.1.4   | Enhanced support for co-location of NFs. |
| SMF + MB-SMF       | ghcr.io/5g-mag/smf_mb-smf     | 0.1.4   | Rel-17 MB-SMF co-located with SMF.       |
| UPF + MB-UPF       | ghcr.io/5g-mag/upf_mb-upf     | 0.1.4   | Rel-17 MB-UPF co-located with UPF.       |
| AMF (MBS-enhanced) | ghcr.io/5g-mag/amf_with_mbs   | 0.1.4   | Additional Rel-17 MBS feature support.   |


### 5G NR RAN

The following RAN components are provided by 5G-MAG contributors. These also follow 5G-MAG versioning.

| Component        | Image name                    | Version | Remarks |
|------------------|-------------------------------|---------| ------- |
| gNodeB           | ghcr.io/5g-mag/gnb_with_mbs   | 0.1.4   | srsRAN gNodeB enhanced with Rel-17 MBS support (built from [srsRAN_Project_mbs](https://github.com/5G-MAG/srsRAN_Project_mbs)). |
| UE               | ghcr.io/5g-mag/ue_with_mbs    | 0.1.4   | srsRAN UE ehnanced with Rel-17 MBS support (built from `mbs` branch of [srsRAN_4G_mbs](https://github.com/5G-MAG/srsRAN_4G_mbs)). |


### Test applications

The following containers are provided by 5G-MAG contributors. These also follow 5G-MAG versioning.

| Application      | Image name                    | Version | Remarks
|------------------|-------------------------------|---------| ---------------------------------------
| Test MBS AF/AS   | ghcr.io/5g-mag/test_mbs_af_as | 0.1.4   | Test application for MB-SMF and MB-UPF.


## Installing Dependencies

Follow the [steps for your distribution](https://docs.docker.com/engine/install/) and install the docker buildx and docker compose plugins.

## Downloading

The MBS Docker images can be obtained:

* From the 5G-MAG's GitHub Container Registry and pulled with Docker (`docker pull ghcr.io/NAMESPACE/IMAGE_NAME`). This step is not needed if you run Docker compose as per the [Running](#running) section below.
* The Docker images can also be obtained by cloning the repository:

```bash
  cd ~
  git clone --recurse-submodules https://github.com/5G-MAG/rt-mbs-examples.git
```

## Building

You can skip this step if you decide to download the images rather than cloning the repository.

> [!NOTE]
> This method uses the `docker-bake.hcl` file and requires `docker-buildx-plugin`

> [!IMPORTANT]
> When building the images, modify the relevant variables in the `.env` file to use a specific version.

Some images are pulled from the GitHub Container Registry during the build. You need to provide your GitHub username and a Personal Access Token (PAT) with `read:packages` scope. Set them as environment variables before building:

```bash
export GITHUB_USER=your_github_username
export GITHUB_TOKEN=your_personal_access_token
```

> [!WARNING]
> Never hardcode your `GITHUB_USER` or `GITHUB_TOKEN` in any file. Always pass them as environment variables. They are not stored in the `.env` file.

From the top level directory of the repository run:

```bash
  cd rt-mbs-examples
  docker buildx bake
```

## Running

A reference deployment (`internal`) has been created to test this project, which consists of an end-to-end setup with a 5G Core with MBS features, a gNB and a UE.

First modify the `.env` file. Change the `DOCKER_HOST_IP=<your_host_ip_address>` with your machine's IP address, like this `DOCKER_HOST_IP=192.168.1.2`. This lets the UPF + MB-UPF use your machine's Internet connection to route the traffic using NAT.

To run the Docker images follow these steps:

First, create the persistent volumes for the subscriber database (only needed once):

```bash
docker volume create open5gs_db_data
docker volume create open5gs_db_config
```

Then start the stack:

```bash
# to use the internal deployment
docker compose -f compose-files/internal/docker-compose-mbs.yml --env-file=.env up -d
```

```bash
# to tear down the internal deployment
docker compose -f compose-files/internal/docker-compose-mbs.yml --env-file=.env down
```
### Establishing a 5G-MBS Broadcast session and sending video

To create a 5G-MBS Broadcast session:

```bash
docker exec -it test_mbs_af_as sendrequest
```
With this command the *Test AF/AS* sends a request to the MB-SMF. 

After sending the request the UE can be started in another terminal to receive the content:

```bash
docker exec -it ue_with_mbs receivevideo
```

To start sending a sample MPEG-2 Transport Stream from the *Test AF/AS*:

```bash
docker exec -it test_mbs_af_as sendvideo
```
This will use a sample MPEG-2 Transport Stream that is inside the AF container. If everything works, the UE terminal should display as ASCII representation of the decoded video component in the MPEG-2 Transport Stream.

## Docker Monitor

A lightweight web-based monitor is available to inspect the status of all running containers grouped by service. It connects to the Docker socket and exposes a UI on port 3002. It is provided by the [rt-common-shared](https://github.com/5G-MAG/rt-common-shared) repository.

Clone it first if you have not already done so:

```bash
git clone https://github.com/5G-MAG/rt-common-shared.git
```

Then set `COMMON_SHARED_PATH` in the `.env` file to the absolute path of the cloned directory:

```
COMMON_SHARED_PATH=/absolute/path/to/rt-common-shared
```

Start the monitor from the `mbs-docker-setup` folder:

```bash
docker compose -f /absolute/path/to/rt-common-shared/docker-monitor/docker-compose-monitor.yml --env-file=.env up -d
```

Then open **http://localhost:3002** in your browser.

> [!NOTE]
> The monitor requires the `5g-mag` Docker network to exist. Start the MBS setup first before launching the monitor.
