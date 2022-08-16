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

while read rawcmd;
do

    echo "Incoming request send: [$rawcmd] to inverter."
    /opt/inverter-cli/bin/inverter_poller -r "$rawcmd";

done < <(mosquitto_sub -h "$MQTT_SERVER" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -i "$MQTT_CLIENTID" -t "$MQTT_TOPIC/sensor/$MQTT_DEVICENAME" -q 1)
