# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG OPEN5GS_VERSION="v2.7.1"
ARG UBUNTU_VERSION="noble"

FROM ubuntu:${UBUNTU_VERSION}

# target container architecture
ARG TARGETARCH

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"
ARG YQ_VERSION="v4.30.6"

# install dependencies
RUN apt-get update && apt-get install libssl-dev libtalloc-dev libtins-dev \
    libyaml-dev iproute2 iptables wget libmicrohttpd-dev smcroute tcpdump gdb tini -y

# install yq
RUN wget --quiet https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH} -O /usr/bin/yq && chmod +x /usr/bin/yq

# copy helper_functions and entrypoint scripts
COPY ./helper_functions.sh /usr/local/bin/helper_functions.sh
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# create directory to store the logs
RUN mkdir -p /var/log/open5gs/

#ENTRYPOINT [ "entrypoint.sh" ]
ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]

# use CMD to provide arguments to ENTRYPOINT (can be overridden by user)
CMD [ "-c", "/open5gs/install/etc/open5gs/upf.yaml" ]
