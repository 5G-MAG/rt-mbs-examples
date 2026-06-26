<h1 align="center">MBS Examples</h1>
<p align="center">
  <img src="https://img.shields.io/badge/Status-Under_Development-yellow" alt="Under Development">
  <img src="https://img.shields.io/badge/License-5G--MAG%20Public%20License%20(v1.0)-blue" alt="License">
</p>

## Introduction

Example projects that make use of other 5G-MAG repositories or provide additional functionality to test and implement new features for MBS.

Additional information can be found at: https://5g-mag.github.io/Getting-Started/pages/5g-multicast-broadcast-services/

## 5G Multicast Broadcast Services - Docker Compose Setup

This folder provides a docker setup to build and run MBS-related 5GC network functions, an MBS-enabled gNB, an MBS-enabled UE and a test AF/AS. In addition, it includes a Docker Compose file to deploy all these components. The configuration files included in this project can be edited on the host machine and are mounted to the respective Docker container during runtime.

Information can be found [here](./mbs-docker-setup/).

## Docker Monitor

A lightweight web-based monitor for inspecting the status of Docker containers grouped by service. It is provided as a shared tool by the [rt-common-shared](https://github.com/5G-MAG/rt-common-shared) repository.

Information on how to set it up can be found in the [mbs-docker-setup README](./mbs-docker-setup/README.md#docker-monitor).

## Express Mock AF

This folder provides a very simple HTTP server that implements a basic set of object downloads with varying redirections. This server is intended to be used for development when static responses are enough to implement or test a new feature.

Information can be found [here](./express-mock-media-server/).

## Insomnia collection

This folder contains Insomnia REST API collections for testing and exploring the 5G-MAG MBS network functions. Each collection targets a specific network function and covers the relevant 3GPP service APIs.

Information can be found [here](./insomnia/).

## TMUX Setup

This folder contains scripts for tmux an open-source terminal multiplexer that allows users to manage multiple terminal sessions, windows, and panes from a single screen or terminal window.

Information can be found [here](./scripts/tmux/).

## Acknowledgements

The reference implementation of the MBS features was partially funded by the European Union through the project 6G-SANDBOX (Grant Agreement 101096328) and by the European Space Agency (ESA) through the project "Requirements consolidation and design concepts for future NTN MBS systems" (ESA Contract No. 5001042231).
