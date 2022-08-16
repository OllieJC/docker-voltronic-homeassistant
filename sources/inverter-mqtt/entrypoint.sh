#!/usr/bin/env bash
set -e
export TERM=xterm

DEVICE=$(grep -Ei "^device=" "/etc/inverter/inverter.conf" | cut -c8- | tr -d "\n")
if [[ -z "$DEVICE" ]]; then
  echo "device not found in /etc/inverter/inverter.conf, exiting!"
  exit 1
fi
echo "Found $DEVICE from config file"

SERIAL_OUTPUT=$(setserial -g "$DEVICE" | sort -V)
if echo "$SERIAL_OUTPUT" | grep -q "Operation not permitted"; then
  echo "$SERIAL_OUTPUT"
  exit 1
fi
echo "$DEVICE appears to be accessible"
echo "$SERIAL_OUTPUT"

echo "Attempting to set baud rate and raw for $DEVICE..."
stty -F "$DEVICE" 2400 raw || exit 1

echo "Starting processes..."

# Init the mqtt server for the first time, then every 5 minutes
# This will re-create the auto-created topics in the MQTT server if HA is restarted...
if [[ -z "$(pgrep -f 'watch.*mqtt-init')" ]]; then
  echo "mqtt-init.sh not running, starting..."
  watch -n 300 /opt/inverter-mqtt/mqtt-init.sh > /dev/null 2>&1 &
else
  echo "mqtt-init.sh is already running"
fi

# Run the MQTT Subscriber process in the background (so that way we can change the configuration on the inverter from home assistant)
if [[ -z "$(pgrep -f mosquitto_sub)" ]]; then
  echo "mqtt-subscriber.sh (mosquitto_sub) not running, starting..."
  /opt/inverter-mqtt/mqtt-subscriber.sh &
else
  echo "mqtt-subscriber.sh (mosquitto_sub) is already running"
fi

# execute exactly every 30 seconds...
# watch -n 30 /opt/inverter-mqtt/mqtt-push.sh > /dev/null 2>&1
if [[ -z "$(pgrep -f 'watch.*mqtt-push')" ]]; then
  echo "mqtt-push not running, starting..."
  watch -n 8 /opt/inverter-mqtt/mqtt-push.sh > /dev/null 2>&1
else
  echo "mqtt-push.sh is already running"
fi
