# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG SRSRAN_PROJECT_BRANCH
ARG DEBIAN_FRONTEND="noninteractive"
ARG GITHUB_USER
ARG GITHUB_TOKEN

# install dependencies
RUN apt-get update && apt-get install cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev \
    libyaml-cpp-dev libgtest-dev libzmq3-dev git libtool -y

# clone czmq repository
RUN git clone --depth 1 https://github.com/zeromq/czmq.git

# install czmq
RUN cd czmq && ./autogen.sh && ./configure && make && make install && ldconfig

# clone the specific srsRAN_Project version
RUN git clone --recurse-submodules --depth 1 --branch=${SRSRAN_PROJECT_BRANCH} https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/5G-MAG/srsRAN_Project_mbs

# install srsRAN_Project
RUN cd srsRAN_Project_mbs && mkdir build && cd build && cmake ../ -DENABLE_EXPORT=ON -DENABLE_ZEROMQ=ON -DBUILD_TESTS=OFF \
    && make -j `nproc`
