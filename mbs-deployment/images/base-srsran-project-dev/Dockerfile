# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION="jammy"

FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev \
    libyaml-cpp-dev libgtest-dev libzmq3-dev git libtool libuhd-dev uhd-host -y

# install czmq
RUN git clone --depth 1 https://github.com/zeromq/czmq.git && cd czmq \
    && ./autogen.sh && ./configure && make && make install && ldconfig
