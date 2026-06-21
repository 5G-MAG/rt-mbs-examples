# Docker Monitor

A lightweight web-based monitor for the MBS Docker setup. It connects to the Docker socket and displays the status of all running containers grouped by service, with live log streaming.

## Requirements

- The `5g-mag` Docker network must exist (i.e., the MBS setup must be running)
- The `.env` file from `mbs-docker-setup/` is used to pass version variables

## Running

From the `mbs-docker-setup/` directory:

```bash
docker compose -f ../monitor/docker-compose-monitor.yml --env-file=.env up -d
```

Then open **http://localhost:3002** in your browser.

## Stopping

```bash
docker compose -f ../monitor/docker-compose-monitor.yml down
```

## Project structure

```
monitor/
  Dockerfile                  Container definition
  server.js                   Express server — proxies Docker socket API
  public/
    index.html                Web UI
  docker-compose-monitor.yml  Compose file to deploy the monitor
```
