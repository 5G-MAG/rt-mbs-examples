# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG OPEN5GS_VERSION="v2.7.1"
ARG UBUNTU_VERSION="noble"

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install libgnutls28-dev libgcrypt-dev libtalloc-dev \
    libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev libyaml-dev libsctp-dev libidn11-dev gdb tini -y

# copy entrypoint script
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# create directory to store the logs
RUN mkdir -p /var/log/open5gs/

#ENTRYPOINT [ "entrypoint.sh" ]
ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]

# use CMD to provide arguments to ENTRYPOINT (can be overridden by user)
CMD [ "-c", "/open5gs/install/etc/open5gs/smf.yaml" ]
