# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG FIVEG_MAG_MBS_VERSION
ARG UBUNTU_VERSION

FROM base-mbs-srsran-4g:${FIVEG_MAG_MBS_VERSION} AS builder

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install libfftw3-dev libmbedtls-dev libboost-program-options-dev \
    libzmq3-dev dnsutils iproute2 iputils-ping -y

# copy executable, default config and libs
COPY --from=builder /srsRAN_4G_mbs/build/srsue/src/srsue /usr/local/bin/srsue
COPY --from=builder /srsRAN_4G_mbs/srsue/ue.conf.example /etc/srsRAN_4G/default/ue.conf.example
COPY --from=builder /srsRAN_4G_mbs/build/lib/src/phy/rf/libsrsran_rf.so.0 \
    /srsRAN_4G_mbs/build/lib/src/phy/rf/libsrsran_rf_zmq.so /usr/local/lib/

# configure dynamically linked libraries
RUN ldconfig

# copy helper_functions and entrypoint scripts
COPY ./helper_functions.sh /usr/local/bin/helper_functions.sh
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# output logs to stdout
RUN ln -sf /dev/stdout /tmp/ue_with_mbs.log

ENTRYPOINT [ "entrypoint.sh" ]

# use CMD to provide arguments to ENTRYPOINT (can be overridden by user)
CMD [ "/etc/srsRAN_4G/default/ue.conf.example" ]
