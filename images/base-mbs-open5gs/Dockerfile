# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION="noble"

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG OPEN5GS_BRANCH="5mbs"
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install python3-pip python3-setuptools python3-wheel ninja-build build-essential \
	  flex bison git cmake libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev libmongoc-dev \
	  libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev \
	  libtins-dev libtalloc-dev meson -y

RUN pip3 install "meson>=0.63.0"

# clone the specific open5gs version
RUN git clone --depth 1 --branch=${OPEN5GS_BRANCH} https://github.com/5G-MAG/open5gs

# install open5gs
RUN cd open5gs && meson build --prefix=`pwd`/install && ninja -j `nproc` -C build \
    && cd build && ninja install
