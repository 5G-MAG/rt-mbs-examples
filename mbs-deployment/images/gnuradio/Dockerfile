# syntax=docker/dockerfile:1

FROM ubuntu:jammy

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"


# install dependencies
RUN apt-get update && apt-get install iproute2 iputils-ping dnsutils curl jq ffmpeg tshark tcpreplay tcpdump python3 vim tini gnuradio gettext -y

COPY ./entrypoint.sh /
COPY --from=common helper_functions.sh /
COPY ./zmq_mux_demux.grc.template /

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
