# syntax=docker/dockerfile:1

#FROM ubuntu:jammy
FROM ubuntu:plucky

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
RUN apt-get update && apt-get install iproute2 sendip iputils-ping dnsutils curl jq ffmpeg tshark tcpreplay tcpdump python3 vim tini wget iptables -y

RUN wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -O /usr/local/bin/yt-dlp
RUN chmod +x /usr/local/bin/yt-dlp

# for libflute
RUN apt -y install ninja-build libboost-all-dev libspdlog-dev libtinyxml2-dev libconfig++-dev clang-tidy clang g++-12 cmake libssl-dev git
RUN git clone https://github.com/5G-MAG/rt-libflute.git
RUN cd rt-libflute/ && mkdir build && cd build && cmake -GNinja .. && ninja && cp /rt-libflute/build/examples/flute* /usr/local/bin

COPY *.mp4 /

COPY sendtraffic /usr/local/bin

COPY sendrequest /usr/local/bin
COPY sendvideo /usr/local/bin

COPY tutorialmbstf_sendrequestconfiguresmf /usr/local/bin
COPY tutorialmbstf_sendrequestpull /usr/local/bin
COPY tutorialmbstf_sendrequestpush /usr/local/bin
COPY tutorialmbstf_senddata /usr/local/bin
COPY tutorialmbstf_sendrequestdashpull /usr/local/bin
COPY tutorialmbstf_sendrequestactivatedistribution /usr/local/bin
COPY tutorialmbstf_sendrequestdashpush /usr/local/bin
COPY tutorialmbstf_sendmpd /usr/local/bin

COPY increasettl /usr/local/bin
COPY push-croatia-live.mpd /

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
