#!/usr/bin/env bash
#
# Simple script to register the MQTT topics when the container starts for the first time...
set -e

MQTT_JSON=$(cat /etc/inverter/mqtt.json)
MQTT_SERVER=$(echo "$MQTT_JSON" | jq '.server' -r)
MQTT_PORT=$(echo "$MQTT_JSON" | jq '.port' -r)
MQTT_TOPIC=$(echo "$MQTT_JSON" | jq '.topic' -r)
MQTT_DEVICENAME=$(echo "$MQTT_JSON" | jq '.devicename' -r)
MQTT_USERNAME=$(echo "$MQTT_JSON" | jq '.username' -r)
MQTT_PASSWORD=$(echo "$MQTT_JSON" | jq '.password' -r)
MQTT_CLIENTID=$(echo "$MQTT_JSON" | jq '.clientid' -r)

registerTopic () {
    if [[ -z "$5" ]]; then
      ENTITY_TYPE="sensor"
    else
      ENTITY_TYPE="$5"
    fi
    DATA_TO_SEND="{
            \"name\": \"${MQTT_DEVICENAME}_$1\",
            \"unit_of_measurement\": \"$2\",
            \"state_topic\": \"${MQTT_TOPIC}/${ENTITY_TYPE}/${MQTT_DEVICENAME}_$1\""
    if [[ -n "$3" ]]; then
        DATA_TO_SEND="${DATA_TO_SEND},
            \"icon\": \"mdi:$3\""
    fi
    if [[ -n "$4" ]]; then
        DATA_TO_SEND="${DATA_TO_SEND},
            \"device_class\": \"$4\""
    fi
    DATA_TO_SEND="${DATA_TO_SEND}
            }"
    mosquitto_pub \
        -h "$MQTT_SERVER" \
        -p "$MQTT_PORT" \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -i "$MQTT_CLIENTID" \
        -t "${MQTT_TOPIC}/${ENTITY_TYPE}/${MQTT_DEVICENAME}_$1/config" \
        -m "$DATA_TO_SEND"
}

registerInverterRawCMD () {
    mosquitto_pub \
        -h "$MQTT_SERVER" \
        -p "$MQTT_PORT" \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -i "$MQTT_CLIENTID" \
        -t "$MQTT_TOPIC/sensor/$MQTT_DEVICENAME/config" \
        -m "{
            \"name\": \"${MQTT_DEVICENAME}\",
            \"state_topic\": \"$MQTT_TOPIC/sensor/$MQTT_DEVICENAME\"
        }"
}

registerTopic "QPIGS_raw" "" "about" "" ""
registerTopic "QPIRI_raw" "" "about" "" ""
registerTopic "Q1_raw" "" "about" "" ""
registerTopic "QMOD_raw" "" "about" "" ""
registerTopic "Warnings" "" "about" "" ""
registerTopic "Inverter_mode" "" "solar-power" "" "" # 1 = Power_On, 2 = Standby, 3 = Line, 4 = Battery, 5 = Fault, 6 = Power_Saving, 7 = Unknown
registerTopic "AC_grid_voltage" "V" "power-plug" "voltage" ""
registerTopic "AC_grid_frequency" "Hz" "current-ac" "frequency" ""
registerTopic "AC_out_voltage" "V" "power-plug" "voltage" ""
registerTopic "AC_out_frequency" "Hz" "current-ac" "frequency" ""
registerTopic "PV_in_voltage" "V" "solar-panel-large" "voltage" ""
registerTopic "PV_in_current" "A" "solar-panel-large" "current" ""
registerTopic "PV_in_watts" "W" "solar-panel-large" "power" ""
registerTopic "PV_charging_power" "W" "solar-panel-large" "power" ""
registerTopic "PV_in_watthour" "Wh" "solar-panel-large" "energy" ""
registerTopic "SCC_voltage" "V" "current-dc" "voltage" ""
registerTopic "Load_pct" "%" "brightness-percent" "" ""
registerTopic "Load_watt" "W" "chart-bell-curve" "power" ""
registerTopic "Load_watthour" "Wh" "chart-bell-curve" "energy" ""
registerTopic "Load_va" "VA" "chart-bell-curve" "" ""
registerTopic "Bus_voltage" "V" "details" "voltage" ""
registerTopic "Heatsink_temperature" "°C" "" "temperature" ""
registerTopic "Battery_capacity" "%" "" "battery" ""
registerTopic "Battery_voltage" "V" "battery-outline" "voltage" ""
registerTopic "Battery_charge_current" "A" "current-dc" "current" ""
registerTopic "Battery_discharge_current" "A" "current-dc" "current" ""
registerTopic "Load_status_on" "" "power" "power" "binary_sensor"
registerTopic "SCC_charge_on" "" "power" "power" "binary_sensor"
registerTopic "AC_charge_on" "" "power" "power" "binary_sensor"
registerTopic "Floating_mode" "" "power" "power" "binary_sensor"
registerTopic "Switch_on" "" "power" "power" "binary_sensor"
registerTopic "Battery_recharge_voltage" "V" "current-dc" "voltage" ""
registerTopic "Battery_under_voltage" "V" "current-dc" "voltage" ""
registerTopic "Battery_bulk_voltage" "V" "current-dc" "voltage" ""
registerTopic "Battery_float_voltage" "V" "current-dc" "voltage" ""
registerTopic "Max_grid_charge_current" "A" "current-ac" "current" ""
registerTopic "Max_charge_current" "A" "current-ac" "current" ""
registerTopic "Out_source_priority" "" "grid" "" ""
registerTopic "Charger_source_priority" "" "solar-power" "" ""
registerTopic "Battery_redischarge_voltage" "V" "battery-negative" "voltage" ""

# Add in a separate topic so we can send raw commands from assistant back to the inverter via MQTT (such as changing power modes etc)...
registerInverterRawCMD
