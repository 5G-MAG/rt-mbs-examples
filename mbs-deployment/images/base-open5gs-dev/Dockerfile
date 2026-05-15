# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION="noble"

FROM ubuntu:${UBUNTU_VERSION}

# install dependencies
RUN apt-get update && apt-get install python3-pip python3-setuptools python3-wheel ninja-build build-essential \
	flex bison git cmake libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev libmongoc-dev \
	libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev \
	libtins-dev libtalloc-dev meson -y
