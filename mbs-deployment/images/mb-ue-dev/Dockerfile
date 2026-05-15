# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG SRSRAN_VERSION="test-mbs"
ARG UBUNTU_VERSION="jammy"

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install libfftw3-dev libmbedtls-dev libboost-program-options-dev libzmq3-dev dnsutils iproute2 iputils-ping tcpdump gdb mpv smcroute iptables ffmpeg net-tools tshark tcpreplay vim tini gettext libuhd-dev uhd-host socat -y

RUN uhd_images_downloader

# for libflute
RUN apt -y install ninja-build libboost-all-dev libspdlog-dev libtinyxml2-dev libconfig++-dev clang-tidy clang g++-12 cmake libssl-dev git
RUN git clone https://github.com/5G-MAG/rt-libflute.git
RUN cd rt-libflute/ && mkdir build && cd build && cmake -GNinja .. && ninja && cp /rt-libflute/build/examples/flute* /usr/local/bin

# copy helper_functions and entrypoint scripts
COPY --from=common helper_functions.sh /usr/local/bin/helper_functions.sh
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

COPY ./receivevideo /usr/local/bin

COPY ./receiveflute /usr/local/bin
COPY ./savevideo /usr/local/bin

COPY ./forwardtraffic /usr/local/bin
COPY ./dropeth0 /usr/local/bin

COPY ./playdashvideo /usr/local/bin
COPY ./savedashvideo /usr/local/bin
COPY ./forwarddashvideo /usr/local/bin

ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]
