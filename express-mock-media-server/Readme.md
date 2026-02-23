# Express Mock Media Server

## Introduction

This project provides a very simple HTTP server that implements a basic set of object downloads with varying
redirections.

This server is intended to be used for development when static responses are enough to implement or test a new feature.

## Downloading

The source can be obtained by cloning the github repository.

```
cd ~
git clone https://github.com/5G-MAG/rt-mbs-examples.git
```

## Building

````
cd ~/rt-mbs-examples/express-mock-media-server
npm install
```` 

## Running

````
cd ~/rt-mbs-examples/express-mock-media-server
npm start
```` 

The server is started on port `3004` per default, this can be changed by setting the PORT environment variable.

## Docker

You can also build and run the server in a docker container. For that purpose execute the following steps:

```
cd ~/rt-mbs-examples/express-mock-media-server/docker
docker compose up --build
```
