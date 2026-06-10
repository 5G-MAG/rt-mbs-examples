# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG UBUNTU_VERSION

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install iproute2 sendip iputils-ping dnsutils curl jq python3-pip -y

# copy test requirements.txt file
COPY ./test/requirements.txt requirements.txt

# install test dependencies
RUN pip install -r requirements.txt

# copy entrypoint scripts
COPY ./images/test_mbs_af_as/entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
