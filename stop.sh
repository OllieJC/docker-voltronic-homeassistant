#!/usr/bin/env bash
set -e

# exit

INSTALL_PATH="/opt/ha-inverter-mqtt-agent"
CONTAINER_NAME=$(grep -Ei "^container_name=" "${INSTALL_PATH}/config/docker.conf" | cut -c16- | tr -d "\n")
DEVICE=$(grep -Ei "^device=" "${INSTALL_PATH}/config/inverter.conf" | cut -c8- | tr -d "\n")

if [ "$(systemctl is-active docker)" = "active" ]; then

  RUNNING=$(docker ps -f name="${CONTAINER_NAME}" -q | tr -d '\n')
  if [[ -n "$RUNNING" ]]; then
    echo "$CONTAINER_NAME is running, stopping..."
    cd "$INSTALL_PATH" || exit 1

    export CONTAINER_NAME="$CONTAINER_NAME"
    export DEVICE="$DEVICE"

    docker-compose down
  else
    echo "$CONTAINER_NAME is not running."
  fi

else
  echo "docker isn't started yet, attempting to start it for the next run..."
fi
