#!/usr/bin/env bash
# set -e

MQTT_JSON=$(cat /etc/inverter/mqtt.json)
MQTT_SERVER=$(echo "$MQTT_JSON" | jq '.server' -r)
MQTT_PORT=$(echo "$MQTT_JSON" | jq '.port' -r)
MQTT_TOPIC=$(echo "$MQTT_JSON" | jq '.topic' -r)
MQTT_DEVICENAME=$(echo "$MQTT_JSON" | jq '.devicename' -r)
MQTT_USERNAME=$(echo "$MQTT_JSON" | jq '.username' -r)
MQTT_PASSWORD=$(echo "$MQTT_JSON" | jq '.password' -r)
MQTT_CLIENTID=$(echo "$MQTT_JSON" | jq '.clientid' -r)

pushMQTTData () {
    if [[ -z "$3" ]]; then
      ENTITY_TYPE="sensor"
    else
      ENTITY_TYPE="$3"
    fi

    MSG=$(echo "$2" | tr -d "\r" | tr -d "\n")
    if [[ "$ENTITY_TYPE" == "binary_sensor" ]]; then
      if [[ "$MSG" == "0" ]]; then
        MSG="OFF"
      fi
      if [[ "$MSG" == "1" ]]; then
        MSG="ON"
      fi
    fi

    #echo "Pushing \"$MSG\" to: ${MQTT_TOPIC}/${ENTITY_TYPE}/${MQTT_DEVICENAME}_$1"

    mosquitto_pub \
        -h "$MQTT_SERVER" \
        -p "$MQTT_PORT" \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -i "$MQTT_CLIENTID" \
        -t "${MQTT_TOPIC}/${ENTITY_TYPE}/${MQTT_DEVICENAME}_$1" \
        --qos 0 \
        -m "$MSG"

    if [[ "$INFLUX_ENABLED" == "true" ]] ; then
        pushInfluxData "$1" "$2"
    fi
}

pushInfluxData () {
    INFLUX_HOST=$(echo "$MQTT_JSON" | jq '.influx.host' -r)
    INFLUX_USERNAME=$(echo "$MQTT_JSON" | jq '.influx.username' -r)
    INFLUX_PASSWORD=$(echo "$MQTT_JSON" | jq '.influx.password' -r)
    INFLUX_DEVICE=$(echo "$MQTT_JSON" | jq '.influx.device' -r)
    INFLUX_PREFIX=$(echo "$MQTT_JSON" | jq '.influx.prefix' -r)
    INFLUX_DATABASE=$(echo "$MQTT_JSON" | jq '.influx.database' -r)
    INFLUX_MEASUREMENT_NAME=$(echo "$MQTT_JSON" | jq '.influx.namingMap.'"$1"'' -r)

    curl -i -XPOST "$INFLUX_HOST/write?db=$INFLUX_DATABASE&precision=s" -u "$INFLUX_USERNAME:$INFLUX_PASSWORD" --data-binary "$INFLUX_PREFIX,device=$INFLUX_DEVICE $INFLUX_MEASUREMENT_NAME=$2"
}

getJSONValue () {
  if [ -z "$1" ]; then
    echo ""
  else
    if [ -z "$2" ]; then
      echo ""
    else
      VAL=$(echo "$1" | pcregrep -o1 "\"$2\":\s*\"?(.*?)\s*[\",]")
      # VAL=$(echo "$1" | jq ".$2" -r | tr -d "\n")
      if [ -n "$VAL" ]; then
        if [ "$VAL" == "null" ]; then
          echo ""
        else
          echo "$VAL"
        fi
      else
        echo ""
      fi
    fi
  fi
}

pushJSONValue () {
  if [ -z "$1" ]; then
    echo "JSON not found"
  else
    if [ -z "$2" ]; then
      echo "JSON variable to fetch is empty"
    else

      VAL=$(getJSONValue "$1" "$2")
      if [ -n "$VAL" ]; then
        if [ -n "$3" ]; then
          FIELD="$3"
        else
          FIELD="$2"
        fi
        pushMQTTData "$FIELD" "$VAL" "$4"
      fi

    fi
  fi
}

handleJson () {
    TYPE=$(getJSONValue "$1" "type")

    case "$TYPE" in

      "QMOD")
        pushJSONValue "$1" "raw" "QMOD_raw" ""
        pushJSONValue "$1" "Inverter_mode" "" ""
        ;;

      "QPIGS")
        pushJSONValue "$1" "raw" "QPIGS_raw" ""
        pushJSONValue "$1" "AC_grid_voltage" "" ""
        pushJSONValue "$1" "AC_grid_frequency" "" ""
        pushJSONValue "$1" "AC_out_voltage" "" ""
        pushJSONValue "$1" "AC_out_frequency" "" ""
        pushJSONValue "$1" "PV_in_voltage" "" ""
        pushJSONValue "$1" "PV_in_current" "" ""
        pushJSONValue "$1" "PV_in_watts" "" ""
        pushJSONValue "$1" "PV_charging_power" "" ""
        pushJSONValue "$1" "PV_in_watthour" "" ""
        pushJSONValue "$1" "SCC_voltage" "" ""
        pushJSONValue "$1" "Load_pct" "" ""
        pushJSONValue "$1" "Load_watt" "" ""
        pushJSONValue "$1" "Load_watthour" "" ""
        pushJSONValue "$1" "Load_va" "" ""
        pushJSONValue "$1" "Bus_voltage" "" ""
        pushJSONValue "$1" "Heatsink_temperature" "" ""
        pushJSONValue "$1" "Battery_capacity" "" ""
        pushJSONValue "$1" "Battery_voltage" "" ""
        pushJSONValue "$1" "Battery_charge_current" "" ""
        pushJSONValue "$1" "Battery_discharge_current" "" ""
        pushJSONValue "$1" "Load_status_on" "" "binary_sensor"
        pushJSONValue "$1" "SCC_charge_on" "" "binary_sensor"
        pushJSONValue "$1" "AC_charge_on" "" "binary_sensor"
        pushJSONValue "$1" "Floating_mode" "" "binary_sensor"
        pushJSONValue "$1" "Switch_on" "" "binary_sensor"
        pushJSONValue "$1" "PV_in_watthour" "" ""
        ;;

      "QPIRI")
        pushJSONValue "$1" "raw" "QPIRI_raw" ""
        pushJSONValue "$1" "Battery_recharge_voltage" "" ""
        pushJSONValue "$1" "Battery_under_voltage" "" ""
        pushJSONValue "$1" "Battery_bulk_voltage" "" ""
        pushJSONValue "$1" "Battery_float_voltage" "" ""
        pushJSONValue "$1" "Max_grid_charge_current" "" ""
        pushJSONValue "$1" "Max_charge_current" "" ""
        pushJSONValue "$1" "Out_source_priority" "" ""
        pushJSONValue "$1" "Charger_source_priority" "" ""
        pushJSONValue "$1" "Battery_redischarge_voltage" "" ""
        ;;

      *)
        if [ -n "$TYPE" ]; then
          pushJSONValue "$1" "raw" "${TYPE}_raw" ""
        else
          echo "Unknown type seen: $1"
        fi
        ;;

    esac
}

/opt/inverter-cli/bin/inverter_poller | while read -r rawjson; do
  if [ -n "$rawjson" ]; then
    handleJson "$rawjson"
  fi
done

