# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
ARG UBUNTU_VERSION="jammy"

FROM ubuntu:${UBUNTU_VERSION}

# build-time arguments
ARG DEBIAN_FRONTEND="noninteractive"

# install dependencies
#RUN apt-get update && apt-get install iproute2 sendip iputils-ping dnsutils curl jq python3-pip -y
RUN apt-get update && apt-get install iproute2 sendip iputils-ping dnsutils curl jq ffmpeg tshark tcpreplay tcpdump python3-pip vim tini wget iptables -y

COPY ./images/test_mbs_af_as/*.mp4 /
# copy scripts
COPY ./images/test_mbs_af_as/sendtraffic /usr/local/bin/sendtraffic
COPY ./images/test_mbs_af_as/sendrequest /usr/local/bin/sendrequest
COPY ./images/test_mbs_af_as/sendvideo /usr/local/bin/sendvideo

RUN chmod +x /usr/local/bin/sendtraffic
RUN chmod +x /usr/local/bin/sendrequest
RUN chmod +x /usr/local/bin/sendvideo
 
# copy test requirements.txt file
COPY ./test/requirements.txt requirements.txt

# install test dependencies
RUN pip install -r requirements.txt

# copy entrypoint scripts
#COPY ./images/test_mbs_af_as/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
#ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["sleep", "infinity"]
