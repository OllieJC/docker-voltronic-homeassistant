#!/usr/bin/env bash
set -e

MQTT_JSON=$(cat /etc/inverter/mqtt.json)
MQTT_SERVER=$(echo "$MQTT_JSON" | jq '.server' -r)
MQTT_PORT=$(echo "$MQTT_JSON" | jq '.port' -r)
MQTT_TOPIC=$(echo "$MQTT_JSON" | jq '.topic' -r)
MQTT_DEVICENAME=$(echo "$MQTT_JSON" | jq '.devicename' -r)
MQTT_USERNAME=$(echo "$MQTT_JSON" | jq '.username' -r)
MQTT_PASSWORD=$(echo "$MQTT_JSON" | jq '.password' -r)
MQTT_CLIENTID=$(echo "$MQTT_JSON" | jq '.clientid' -r)

echo "Subscribing to: $MQTT_TOPIC/sensor/$MQTT_DEVICENAME"

CURRENT_CMD=""

while read rawcmd;
do

    if [ "$CURRENT_CMD" != "$rawcmd" ]; then
        echo "Incoming request send: [$rawcmd] to inverter."

        echo "Killing any running inverter_poller"
        pgrep -f "inverter_poller|mqtt-push" | xargs kill -s 9
        sleep 3s

        echo "Sending: [$rawcmd] to inverter."
        /opt/inverter-cli/bin/inverter_poller -r "$rawcmd"
        sleep 1s

        CURRENT_CMD="$rawcmd"

        echo "Rerunning entrypoint.sh"
        /opt/inverter-mqtt/entrypoint.sh &
    fi

done < <(mosquitto_sub -h "$MQTT_SERVER" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -i "$MQTT_CLIENTID" -t "$MQTT_TOPIC/sensor/$MQTT_DEVICENAME" -q 2)
