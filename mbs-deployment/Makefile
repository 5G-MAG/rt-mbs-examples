# include docker-compose .env file
include .env

.PHONY: build-all build-base-open5gs build-base-srsran-project build-base-srsran-4g build-gnb build-ue build-af build-gnuradio compile-open5gs compile-gnb compile-ue compile-all gdb-upf gdb-ue up down restart ps copyvideo copyvideo1 copyvideo2 build-mbstf build-mediaserver ips mpvhost

build-all:
	docker buildx bake

build-base-open5gs:
	docker buildx bake base-open5gs-dev

build-base-srsran-project:
	docker buildx bake base-srsran-project-dev

build-base-srsran-4g:
	docker buildx bake base-srsran-4g-dev

build-gnb:
	docker buildx bake mb-gnb-dev

build-ue:
	docker buildx bake mb-ue-dev

build-af:
	docker buildx bake af-dev
	
build-gnuradio:
	docker buildx bake gnuradio

compile-open5gs:
	docker run --rm --mount "type=bind,source=${COMPILE_PATH}/open5gs,target=/open5gs" "base-open5gs-dev:${OPEN5GS_MBS_VERSION}" sh -c 'cd open5gs &&   meson build --prefix=/open5gs/install && ninja -j `nproc` -C build && cd build && ninja install >/dev/null'

compile-gnb:
	docker run --rm --mount "type=bind,source=${COMPILE_PATH}/rt-srsRAN_Project,target=/rt-srsRAN_Project" "base-srsran-project-dev:${SRSRAN_MBS_VERSION}" sh -c 'cd rt-srsRAN_Project && mkdir -p build && cd build && cmake ../ -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_EXPORT=ON -DENABLE_ZEROMQ=ON -DBUILD_TESTS=OFF -DFORCE_DEBUG_INFO=ON && make -j `nproc`'

compile-ue:
	docker run --rm --mount "type=bind,source=${COMPILE_PATH}/srsRAN_4G,target=/srsRAN_4G" "base-srsran-4g-dev:${SRSRAN_MBS_VERSION}" sh -c 'cd srsRAN_4G && mkdir -p build && cd build && cmake ../ -DENABLE_SRSEPC=OFF -DENABLE_SRSENB=OFF -DENABLE_GUI=OFF -DCMAKE_BUILD_TYPE=Debug&& make -j `nproc`'

compile-all: compile-open5gs compile-gnb compile-ue

gdb-upf:
	docker exec -it mb-upf gdbtui --args /open5gs/install/bin/open5gs-upfd -c /etc/open5gs/custom/mb-upf.yaml

gdb-ue:
	docker exec -it mb-ue gdbtui --args /srsRAN_4G/build/srsue/src/srsue /etc/srsRAN_4G/custom/mod_mb-ue.conf

up:
	docker compose -f compose-files/${COMPOSE_DEPLOYMENT}/docker-compose.yaml --env-file=.env up -d

down:
	docker compose -f compose-files/${COMPOSE_DEPLOYMENT}/docker-compose.yaml --env-file=.env down

restart:
	make down && make up

ps:
	docker compose -f compose-files/${COMPOSE_DEPLOYMENT}/docker-compose.yaml --env-file=.env ps --all

copyvideo:
	docker cp mb-ue:receivedvideo.ts $${HOME}/receivevideo_ue.ts

copyvideo1:
	docker cp mb-ue1:receivedvideo.ts $${HOME}/receivevideo_ue1.ts

copyvideo2:
	docker cp mb-ue2:receivedvideo.ts $${HOME}/receivevideo_ue2.ts

build-mbstf:
	cd ${COMPILE_PATH}/rt-mbs-transport-function && docker build --tag=mbstf:latest -f docker/local/Dockerfile .

build-mediaserver:
	cd ${COMPILE_PATH}/rt-mbs-examples/express-mock-media-server && docker build -f docker/Dockerfile -t mediaserver:latest .

ips:
	docker inspect open5gs | jq '.[0].Containers | .[] | "\(.IPv4Address) \(.Name) "' | sed 's/"//g' | sed 's#/24##'  | sort -t '.' -k4 -n | column -t

mpvhost:
	echo "mpv --vo=caca --profile=low-latency udp://239.0.0.100:9988?localaddr=$$(ip -o a show dev br-gnbue | grep -v inet6 | awk '{print $$4}' | awk -F'/' '{print $$1}')" | bash
