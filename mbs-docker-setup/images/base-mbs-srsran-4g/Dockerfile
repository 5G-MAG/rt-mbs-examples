# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG SRSRAN_4G_BRANCH
ARG DEBIAN_FRONTEND="noninteractive"
ARG GITHUB_USER
ARG GITHUB_TOKEN

# install dependencies
RUN apt-get update && apt-get install build-essential cmake libfftw3-dev libmbedtls-dev \
    libboost-program-options-dev libconfig++-dev libsctp-dev libzmq3-dev git libtool -y

# clone czmq
RUN git clone --depth 1 https://github.com/zeromq/czmq.git

# install czmq
RUN cd czmq && ./autogen.sh && ./configure && make && make install && ldconfig

# clone the specific srsRAN_4G version
RUN git clone --recurse-submodules --depth 1 --branch=${SRSRAN_4G_BRANCH} https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/5G-MAG/srsRAN_4G_mbs

# install srsRAN_4G
RUN cd srsRAN_4G_mbs && mkdir build && cd build \
    && cmake ../ -DENABLE_SRSEPC=OFF -DENABLE_SRSENB=OFF -DENABLE_GUI=OFF -DCMAKE_CXX_FLAGS="-Wno-error=array-bounds" \
    && make -j `nproc`
