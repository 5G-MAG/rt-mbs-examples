# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG SRSRAN_VERSION="test-mbs"
ARG UBUNTU_VERSION="jammy"

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install libfftw3-dev libmbedtls-dev libsctp-dev \
    libyaml-cpp-dev libzmq3-dev dnsutils gdb tcpdump iproute2 tini gettext libuhd-dev uhd-host -y

RUN uhd_images_downloader

# copy helper_functions and entrypoint scripts
COPY --from=common helper_functions.sh /usr/local/bin/helper_functions.sh
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]
