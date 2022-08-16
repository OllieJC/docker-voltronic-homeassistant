#!/usr/bin/env bash
set -e

INSTALL_PATH="/opt/ha-inverter-mqtt-agent"

DEVICE=$(grep -Ei "^device=" "${INSTALL_PATH}/config/inverter.conf" | cut -c8- | tr -d "\n")
if [[ -z "$DEVICE" ]]; then
  echo "device not found in config/inverter.conf, exiting!"
  exit 1
fi

while read p; do
  if [[ -n "$p" ]]; then
    echo "Querying device with command: $p"
    docker run \
      --device "${DEVICE}:${DEVICE}" \
      --entrypoint /opt/inverter-cli/bin/inverter_poller \
      ha-inverter-mqtt-agent_mqtt:latest inverter_poller -d -1 -r "$p"
    echo ""
  fi
done <commands.txt
