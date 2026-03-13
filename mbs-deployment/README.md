# 5g mbs developer deployment
This repository contains the deployment of the MBS 5G core, UE, gNB and MBSTF. This deployment is aimed to development, not a final deployment. The images contain a lot extra packages to ease debugging and testing.

> [!NOTE]
> In this project, the 5G core network functions, UE and gNB are placed in the host's filesystem. In order to be compiled, they are mounted as a docker volume and compiled inside docker containers. Then, the compiled binaries are mounted inside docker containers in order to be run.
This is done this way so that you don't need to compile the whole open5gs and SRS repositories every time you change something.


# Install and run
## Developer directory
Since there are multiple git repositories that depend on each other, we download all the repositories into a single directory. By default, we use *$HOME/Developer*, and this tutorial follows that convention.

If you want to use another directory you can manually change it by editing the .env file (COMPILE_PATH variable). Be careful when copying commands from this readme.

Create the directory with:
```
mkdir -p $HOME/Developer
```

## Clone open5gs and srsRAN to the developer directory
We suppose that you are using github tokens to access the private repositories. Substitute the variables with your own.
```
github_user=<github_user>
github_token=<github_toke>

cd $HOME/Developer
git clone -b upv-mbs "https://${github_user}:${github_token}@github.com/5G-MAG/srsRAN_4G_private.git" srsRAN_4G
git clone -b du-to-mix "https://${github_user}:${github_token}@github.com/5G-MAG/rt-srsRAN_Project_private.git" rt-srsRAN_Project
git clone -b 5mbs-development "https://${github_user}:${github_token}@github.com/5G-MAG/open5gs.git"
git clone -b development --recurse-submodules https://${github_user}:${github_token}@github.com/5G-MAG/rt-mbs-transport-function.git
git clone -b feature/mbsdeployment https://${github_user}:${github_token}@github.com/5G-MAG/rt-mbs-examples.git
```

## Create .env file
.env contains different variables that affect the deployment. You can create it from the template:
```
cd $HOME/Developer/rt-mbs-examples/mbs-deployment
cp env.template .env

# modify DOCKER_HOST_IP variable with the ip of the intarface that has the default route. Works for simple setups, edit manually if it fails.
IP=$(ip -o a show | grep $(ip -o r show | grep default | awk '{print $5}') | grep inet | grep -v inet6 | awk '{print $4}' | awk -F/ '{print $1}')
sed -i "s/<your_user>/$USER/;s/<your_ip>/$IP/" .env
```

## cd to the mbs-deployment directory
```
cd $HOME/Developer/rt-mbs-examples/mbs-deployment
```

## Build the images
```
make build-all
make build-mbstf
make build-mediaserver
```

## Compile core, gnb and ue
```
make compile-open5gs
make compile-gnb
make compile-ue
```

## Start the docker compose deployment
```
make up
```

## Stop the docker compose deployment
```
make down
```

# Files
* compose-files: docker compose files, one subdirectory for every deployment
* configs: config files, one subdirectory for every deployment
* images: image dockerfiles and scripts
* docker-bake.hcl: build configuration
* Makefile: commands
* env.template: template for the .env file


# MBS Broadcast demo
Receive video in the two UEs.
```
docker exec -it mb-ue1 receivevideo
```

```
docker exec -it mb-ue2 receivevideo
```

In another terminal, send request to setup the multicast session, and then send the video.
```
docker exec -it af sendrequest
docker exec -it af sendvideo
```

# MBSTF tutorial commands
Commands to perform the operations in the MBSTF tutorial (https://hub.5g-mag.com/Getting-Started/pages/5g-multicast-broadcast-services/tutorials/mbstf.html)

## "Step by step"
Use this commands if you want to see the requests and responses of every HTTP request. Manually load into your shell the variable that is printed at the end of each command.

### Receive the traffic in the UE
```
docker exec -it mb-ue1 receiveflute
```

```
docker exec -it mb-ue2 receiveflute
```

### SMF configuration
```
docker exec -i af tutorialmbstf_sendrequestconfiguresmf
```

### PULL operation
```
docker exec -i af tutorialmbstf_sendrequestpull "${UDP_TUNNEL_PORT}"
```

### PUSH operation
```
docker exec -i af tutorialmbstf_sendrequestpush "${UDP_TUNNEL_PORT}"
docker exec -i af tutorialmbstf_senddata "${URL}"
```

### DASH PULL operation
```
docker exec -i af tutorialmbstf_sendrequestdashpull "${UDP_TUNNEL_PORT}"
docker exec -i af tutorialmbstf_sendrequestactivatedistribution "${SESSION_ID}"
```

### DASH PUSH operation
```
docker exec -i af tutorialmbstf_sendrequestdashpush "${UDP_TUNNEL_PORT}"
docker exec -i af tutorialmbstf_sendmpd "${URL}"
```

## Just copy and paste
Use this if you just want to copy and paste the commands, the variables get loaded automatically.

### Receive the traffic in the UE
```
docker exec -it mb-ue1 receiveflute
```

```
docker exec -it mb-ue2 receiveflute
```

### SMF configuration
```
eval "$(docker exec -i af tutorialmbstf_sendrequestconfiguresmf | grep UDP_TUNNEL_PORT)"
```

### PULL operation
```
docker exec -i af tutorialmbstf_sendrequestpull "${UDP_TUNNEL_PORT}"
```

### PUSH operation
```
eval "$(docker exec -i af tutorialmbstf_sendrequestpush "${UDP_TUNNEL_PORT}" | grep URL)"
docker exec -i af tutorialmbstf_senddata "${URL}"
```


### DASH PULL operation
```
eval "$(docker exec -i af tutorialmbstf_sendrequestdashpull "${UDP_TUNNEL_PORT}" | grep SESSION_ID)"
docker exec -i af tutorialmbstf_sendrequestactivatedistribution "${SESSION_ID}"
```

### DASH PUSH operation
```
eval "$(docker exec -i af tutorialmbstf_sendrequestdashpush "${UDP_TUNNEL_PORT}" | grep URL)"
docker exec -i af tutorialmbstf_sendmpd "${URL}"
```


# TODO and possible bugs
## Bug with substitution of variables names from docker compose in config files 
It seems that variables such as GNB_IP work, but GNB_ZMQ_IP gets resolved a wrong IP. Probably because of the double "_".

## gnuradio container slow start
The gnuradio container takes a while to start. To confirm that it has started you can do `docker logs -f gnuradio` and wait until you see any output.

# misc
## Create video from the DASH fragments 
```
cat init.mp4 *.m4s > video.mp4
```

## Forward the video from the container to the host
```
docker exec -it mb-ue1 forwarddashvideo
```

Play the video in your local PC:
```
# you need to specify the IP of the bridge
ip_gnbue_bridge=10.33.100.1
mvp "udp://239.0.0.100:1234?localaddr=${ip_gnbue_bridge}"
```

## Forward from host to local pc
```
ip_local_pc=172.30.0.67
socat UDP4-RECV:1234,bind=239.0.0.100,ip-add-membership=239.0.0.100:br-gnbue,reuseaddr "UDP4-SENDTO:${ip_local_pc}:1234"
```


## Forward over ssh
```
ssh -L 7000:localhost:7000 dev3

ffmpeg -re -i udp://239.0.0.100:1234?localaddr=10.33.100.1 -c copy -f mpegts "tcp://127.0.0.1:7000?listen=1"

mpv  tcp://127.0.0.1:7000
```
