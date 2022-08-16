#!/usr/bin/env bash
set -e

# exit

INSTALL_PATH="/opt/ha-inverter-mqtt-agent"

CONTAINER_NAME=$(grep -Ei "^container_name=" "${INSTALL_PATH}/config/docker.conf" | cut -c16- | tr -d "\n")
if [[ -z "$CONTAINER_NAME" ]]; then
  echo "container_name not found in config/docker.conf, exiting!"
  exit 1
fi

DEVICE=$(grep -Ei "^device=" "${INSTALL_PATH}/config/inverter.conf" | cut -c8- | tr -d "\n")
if [[ -z "$DEVICE" ]]; then
  echo "device not found in config/inverter.conf, exiting!"
  exit 1
fi

RUN_START="0"

if [ "$(systemctl is-active docker)" = "active" ]; then

  RUNNING=$(docker ps -f name="${CONTAINER_NAME}" -q | tr -d '\n')
  if [[ -n "$RUNNING" ]]; then

    HEALTHY=$(docker inspect --format="{{.State.Health.Status}}" "${CONTAINER_NAME}" | tr -d "\n")
    if [ "$HEALTHY" == "unhealthy" ]; then
      echo "$CONTAINER_NAME is running, but $HEALTHY, will attempt to stop and start again..."
      "${INSTALL_PATH}/stop.sh"
      RUN_START="1"
    else
      echo "$CONTAINER_NAME (${RUNNING}) is already running (${HEALTHY})"
    fi

  else
    echo "$CONTAINER_NAME is not running!"
    RUN_START="1"
  fi

else
  echo "docker isn't started yet, attempting to start the docker service..."
  sudo systemctl start docker || exit 1
  RUN_START="1"
fi

if [ "$RUN_START" = "1" ]; then
    echo "Starting..."
    cd "$INSTALL_PATH" || exit 1

    sudo stty -F "$DEVICE" sane
    sudo stty -F "$DEVICE" 2400 raw -echo

    export CONTAINER_NAME="$CONTAINER_NAME"
    export DEVICE="$DEVICE"

    docker-compose up -d
fi
