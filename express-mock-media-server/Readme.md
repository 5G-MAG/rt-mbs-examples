# Express Mock Media Server

## Introduction

This project provides a very simple HTTP server that implements a simple set of object downloads with varying redirections.

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
