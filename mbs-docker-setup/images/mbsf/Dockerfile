# syntax=docker/dockerfile:1

# global build-time arguments for FROM statements
# (https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS building

# Add OS dependencies and install Python packages
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y git ninja-build build-essential flex bison libglibmm-2.4-dev libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev libtins-dev libtalloc-dev libpcre2-dev libboost-system-dev libboost-thread-dev libboost-program-options-dev libboost-test-dev libspdlog-dev libtinyxml2-dev libconfig++-dev uuid-dev libxml2-dev gcc-14 g++-14 curl wget default-jdk cmake jq util-linux-extra mm-common python3-pip && \
    for i in cpp g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool lto-dump; do rm -f /usr/bin/$i; ln -s $i-14 /usr/bin/$i; done && \
    python3 -m pip install --break-system-packages --upgrade meson

WORKDIR /source

# clone rt-mbs-function
RUN git clone --recurse-submodules --depth 1 --branch=main https://github.com/5G-MAG/rt-mbs-function.git


WORKDIR /source/rt-mbs-function

RUN rm -rf build
RUN meson setup --prefix /usr --sysconfdir /etc --localstatedir /var build
RUN meson compile -C build
RUN DESTDIR=/install meson install -C build
RUN mkdir -p /install/etc/open5gs && cp build/src/mbsf/mbsf.yaml /install/etc/open5gs/mbsf.yaml

# Remove default configuration for container
RUN rm -f /install/usr/bin/open5gs-[a-ln-z]*

# Create container image
FROM ubuntu:${UBUNTU_VERSION} AS runtime

# Install runtime dependencies
RUN apt update && \
    apt -y install libglibmm-2.4-1t64 libsctp1 libgnutls30t64 libgcrypt20 libssl3t64 libidn12 libmongoc-1.0-0t64 libbson-1.0-0t64 libyaml-0-2 libnghttp2-14 libmicrohttpd12t64 libcurl3t64-gnutls libtins4.5 libtalloc2 libpcre2-16-0 libboost-system1.83.0 libboost-thread1.83.0 libboost-program-options1.83.0 libboost-test1.83.0 libspdlog1.12 libtinyxml2-10 libconfig++9v5 libxml2

# Copy files to be installed
COPY --from=building /install/ /

# Update dynamic library links and cache for the image
RUN ldconfig -v

# Container entrypoint
ENTRYPOINT ["/usr/bin/open5gs-mbsfd"]
