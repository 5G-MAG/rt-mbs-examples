# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG FIVEG_MAG_MBS_VERSION
ARG UBUNTU_VERSION

FROM base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION} AS builder

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install libgnutls28-dev libgcrypt-dev libtalloc-dev \
    libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev libyaml-dev libsctp-dev ethtool -y

# copy executable, default config and libs
COPY --from=builder /open5gs/install/bin/open5gs-nrfd /usr/local/bin/open5gs-nrfd
COPY --from=builder /open5gs/install/etc/open5gs/nrf.yaml /etc/open5gs/default/nrf.yaml
COPY --from=builder /open5gs/install/etc/open5gs/tls/ca.crt /open5gs/install/etc/open5gs/tls/nrf.crt /open5gs/install/etc/open5gs/tls/nrf.key /etc/open5gs/default/tls/
COPY --from=builder /open5gs/install/lib/*/libogscrypt.so.2 /open5gs/install/lib/*/libogsproto.so.2 \
/open5gs/install/lib/*/libogscore.so.2 /open5gs/install/lib/*/libogssbi.so.2 /open5gs/install/lib/*/libogsapp.so.2 \
/open5gs/install/lib/*/libogssbi-openapi.so.2 /usr/local/lib/

# configure dynamically linked libraries
RUN ldconfig

# copy entrypoint script
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

# create directory to store the logs
RUN mkdir -p /var/log/open5gs/

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]

# use CMD to provide arguments to ENTRYPOINT (can be overridden by user)
CMD [ "-c", "/etc/open5gs/default/nrf.yaml" ]
