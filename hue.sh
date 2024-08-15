#!/bin/bash

# Contains HUE_BRIDGE_API, API_KEY and NR_LIGHTS
source /etc/default/hue


light_is_on() {
    curl -s http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1 | jq '.state.on'
}

set_light_state() {
    curl -s -X PUT -d "{\"on\":$2}" -o /dev/null http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1/state;
}

set_state() {
    if [ "$ACTION" == "on" ]; then
        STATE=true
    else
        ACTION="off"
        STATE=false
    fi
}

echo_info() {
    if [ $1 -eq 0 ]; then
        echo "Light $2 turned $3 successfully."
    else
        echo "Failed to turn $3 light $2."
    fi
}


# First arg is not a number -> set state of all lights
if ! [[ $1 =~ ^[0-9]+$ ]]; then
    ACTION=$1
    set_state
    for i in $(seq 1 $NR_LIGHTS);
    do
        set_light_state $i $STATE
        echo_info $? $i $ACTION
    done
    exit 0
fi


# Set state of single light
LIGHT_NR=$1
ACTION=$2

if [ -z $ACTION ]; then # No action -> change state
    echo "skj"
    echo $(light_is_on $LIGHT_NR)
    if [ $(light_is_on $LIGHT_NR) == "true" ]; then
        ACTION="off"
    else
        ACTION="on"
    fi
fi

set_state
set_light_state $LIGHT_NR $STATE
echo_info $? $LIGHT_NR $ACTION
