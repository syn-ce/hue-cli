#!/bin/bash

# Contains HUE_BRIDGE_API, API_KEY, NR_LIGHTS, AUTO_MAPPING_PATH, LIGHT_MAPPING_PATH
source ~/hue-cli/hue_config

declare -A LIGHT_ALIASES
declare -A COMMANDS
declare -A curr_command

NR_LIGHTS=$((NR_LIGHTS + 0)) # Convert to number

# List of lights to operate on
LIGHT_LIST=()

# -- Parse mappings if necessary
if [ ! -e "$AUTO_MAPPING_PATH" ]; then # File for generated mappings doesn't even exist yet
    ~/hue-cli/parse_hue_mappings.sh $LIGHT_MAPPING_PATH $AUTO_MAPPING_PATH
else
    mapping_date=$(date -r $LIGHT_MAPPING_PATH +%s)
    auto_mapping_data=$(date -r $LIGHT_MAPPING_PATH +%s)
    if [ "$mapping_date" -ge "$auto_mapping_data" ]; then # Mappings have changed since last parsing
        ~/hue-cli/parse_hue_mappings.sh $LIGHT_MAPPING_PATH $AUTO_MAPPING_PATH
    fi
fi

# -- Load light-aliases with their light numbers
while IFS='=' read light_alias lights_str; do
    LIGHT_ALIASES[$light_alias]=$lights_str
done < $LIGHT_MAPPING_PATH

echo "LOADED LIGHT_ALIASES:"
for key in ${!LIGHT_ALIASES[@]}
do
    echo " $key=${LIGHT_ALIASES[$key]}"
done

# light_nr, json
set_light_state() {
    error=$(echo $2 | curl -s -X PUT http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1/state \
    --data-binary @- | jq '.[0].error')
    if [ "$error" != "null" ]; then
        echo "Error while setting state of light $1:"
        echo "$error"
        return 1
    fi
    echo "Successfully set state of light $1."
    return 0
}

# Execute the command given as an argument. Command has the form a=b, where a is a list of light aliases and b is a list of properties
# to apply to the lights (both comma-separated). If b is empty, a will be parsed as the light alias list. If that fails, b will be
# assigned a's content and they will be interpreted as a list of properties.
# If a is empty a default list of light aliases will be used, specified in the light mappings. If no default is specified, use all
# lights from 1 to $LIGHT_NR. If b is empty and a does not contain properties, b will be assigned a default value, or 'off' is none is configured.

execute_command() {
    declare -gA curr_command # Clear previous command
    LIGHT_LIST=() # Clear previous lights

    IFS='=' read light_aliases properties <<< $1 # Split command into lights and properties

    IFS='=' read default_light_aliases default_properties <<< ${COMMANDS[__default]} # Split default command into lights and properties

    if [ -v $light_aliases ] && [ -v $properties ]; then
        echo "No light aliases and properties. Falling back to default command '__default'."
        light_aliases=$default_light_aliases
        properties=$default_properties
    else
        if [ -v $light_aliases ]; then # Use the default light-aliases (if no default is specified/it has an empty light list, simply use all lights)
            echo "No light aliases. Using default lights '$default_light_aliases'."
            light_aliases=$default_light_aliases
        fi

        if [ -v $properties ]; then
            try_parse_light_list "$light_aliases" # Try to parse first argument as lights
            if [ $? -ne 0 ]; then # If parsing of light-list was unsuccessful, operate on default (for now all) lights and try to parse as first argument as properties instead
                echo "Failed to parse list of light aliases '$light_aliases'."
                echo "Trying to parse as command instead, operating on all lights."
                properties=$light_aliases
                light_aliases=$default_light_aliases
            else # Parsing of lights was successful -> use default command
                echo "No properties. Falling back to default '$default_properties'."
                properties=$default_properties
            fi
        fi
    fi

    # Check if light_aliases or properties are (still) empty, meaning that the defaults are empty; If so, fallback to all lights / off
    if [ -v $light_aliases ]; then
        LIGHT_LIST=($(seq 1 1 $NR_LIGHTS))
    elif [ ${#LIGHT_LIST[@]} -eq 0 ]; then # Avoid unnecessary double parsing of light_aliases
        try_parse_light_list "$light_aliases" # TODO: add check
        if [ $? -ne 0 ]; then # If parsing of light-list was unsuccessful, operate on default (for now all) lights and try to parse as first argument as properties instead
            echo "Failed to parse list of light aliases '$light_aliases'."
            exit 1
        fi
    fi

    if [ -v $properties ]; then
        properties=off
    fi

    # Construct associative array from properties
    for val in ${properties//,/ }
    do
        case $val in
            "on")
            curr_command["on"]=true
            ;;
            "off")
            curr_command["on"]=false
            ;;
            b[0-9][0-9]*)
            curr_command["bri"]=${val:1}
            ;;
            h[0-9][0-9]*)
            curr_command["hue"]=${val:1}
            ;;
            s[0-9][0-9]*)
            curr_command["sat"]=${val:1}
            ;;
            *)
            echo -n "Unknown property in command '$1': Expected 'on', 'off' or '@(s|h|b)[0-9]+', got '$val'"
            return 1;
            ;;
        esac
    done

    # Construct json from curr_command
    json_str="$(for key in "${!curr_command[@]}"; do
            printf '%s\0%s\0' "$key" "${curr_command[$key]}"
        done |
        jq -Rs '
          split("\u0000")
          | . as $a
          | reduce range(0; length/2) as $i
                ({}; .
                +
                {($a[2*$i]): (
                    if $a[2*$i + 1] == "true" then true
                    elif $a[2*$i + 1] == "false" then false
                    else ($a[2*$i + 1] | fromjson? // .)
                    end
                    )
                })'
    )"

    for light_nr in ${LIGHT_LIST[@]}
    do
        # TODO: check if light_nr is valid light number
        set_light_state $light_nr "$json_str"
    done
}

# Read commands
while IFS=':' read name instructions; do
    COMMANDS[$name]=$instructions
done < hue_commands.txt

echo "LOADED COMMANDS:"
for key in ${!COMMANDS[@]}
do
    echo "$key:${COMMANDS[$key]}"
    #execute_command ${COMMANDS[$key]}
done
# --

light_is_on() {
    curl -s http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1 | jq '.state.on'
}

set_light_state_on() {
    curl -s -X PUT -d "{\"on\":$2}" -o /dev/null http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1/state
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

# Add nr to LIGHT_LIST if it's new
add_light_nr_if_new() {
    if [ -z $1 ]; then # Check if empty TODO: this should not be necessary here
        return
    fi
    # Check if nr already exists; if so, don't add it again. NOTE: quadratic time complexity
    for nr in $LIGHT_LIST
    do
        if [ "$1" -eq "$nr" ]; then
            return
        fi
    done
    # Nr not in list
    LIGHT_LIST+=($1)
}

try_parse_light_list() {
    for light_alias in ${1//,/ }
    do
        if [[ $light_alias =~ ^[0-9]+$ ]]; then # Light-Number
            if (( 0 <= $light_alias && $light_alias  <= $NR_LIGHTS )); then
                add_light_nr_if_new $light_alias
                continue
            else
                return 1
            fi
        fi
        if [ ! -z "${LIGHT_ALIASES[$light_alias]}" ]; then # Light-alias
            for light_nr in "${LIGHT_ALIASES[$light_alias]}"
            do
                add_light_nr_if_new $light_nr
            done
            continue
        else
            return 1
        fi
    done
    return 0
}


# Process command if first arg is command
if [[ -v COMMANDS[$1] ]]; then
    echo "Executing command $1"
    execute_command ${COMMANDS[$1]} # TODO: check for errors
    exit 0
else
    echo "Did not recognize a command."
fi

# Convert the input into a command to be executed

# TODO: make this more intuitive / user-friendly by leaving out the equals-sign etc in the input (and then converting that input to a command here)
# For now, the commands will be expected to look exactly like the ones in the file

execute_command "$1=$2"

# Try to parse light list

#command_str=""
#
#if [ $(try_parse_light_list "$1") != "true" ]; then # If parsing of light-list was unsuccessful, operate on all lights
#    #LIGHT_LIST=($(seq 1 1 $NR_LIGHTS))
#else
#
#fi


#try_parse_light_list $1

# TODO: first check if it's a command
# command=$1
#if [ $(try_parse_light_list "$1") != "true" ]; then # If parsing of light-list was unsuccessful, operate on all lights
#    LIGHT_LIST=($(seq 1 1 $NR_LIGHTS))
#fi

#echo "light list = $LIGHT_LIST"


## First arg is not a number -> set state of all lights
#if ! [[ $1 =~ ^[0-9]+$ ]]; then
#    ACTION=$1
#    set_state
#    for i in $(seq 1 $NR_LIGHTS);
#    do
#        set_light_state_on $i $STATE
#        echo_info $? $i $ACTION
#    done
#    exit 0
#fi
#
#case $ACTION in
#  "on") status="bar" ;;
#  "off") status="buh" ;;
#  "+") status="buh" ;;
#  "-") status="buh" ;;
#   *) status=$status ;;
#esac

# Determine lights to act on
# -> check if it's a list of aliases / light numbers
# i.e. comma-separated light numbers and / or aliases


## Set state of single light
#LIGHT_NR=$1
#ACTION=$2
#
#if [ -z $ACTION ]; then # No action -> DEFAULT_ACTION
#    ACTION=$DEFAULT_ACTION
#    if [ $(light_is_on $LIGHT_NR) == "true" ]; then
#        ACTION="off"
#    else
#        ACTION="on"
#    fi
#fi
#
#set_state
#set_light_state_on $LIGHT_NR $STATE
#echo_info $? $LIGHT_NR $ACTION
