#!/bin/bash

# Contains HUE_BRIDGE_API, API_KEY, NR_LIGHTS, AUTO_MAPPING_PATH, LIGHT_MAPPING_PATH, COMMAND_PATH, DEFAULT_LIGHTS, DEFAULT_PROPERTIES, PRINT(?), DEBUG(?)
source ~/hue-cli/hue_config

print() [[ -v PRINT ]]

debug() [[ -v DEBUG ]]

declare -A LIGHT_ALIASES
declare -A COMMANDS
declare -A curr_instruction

NR_LIGHTS=$((NR_LIGHTS + 0)) # Convert to number

# List of lights to operate on
LIGHT_LIST=()

# -- Parse mappings if necessary
if [ ! -e "$AUTO_MAPPING_PATH" ]; then # File for generated mappings doesn't even exist yet
    debug && echo "File '$AUTO_MAPPING_PATH' does not exist. Parsing '$LIGHT_MAPPING_PATH'."
    ~/hue-cli/parse_hue_mappings.sh $LIGHT_MAPPING_PATH $AUTO_MAPPING_PATH
else
    debug && echo "File '$AUTO_MAPPING_PATH' exists."
    mapping_date=$(date -r "$LIGHT_MAPPING_PATH" +%s)
    auto_mapping_data=$(date -r "$LIGHT_MAPPING_PATH" +%s)
    if [ "$mapping_date" -ge "$auto_mapping_data" ]; then # Mappings have changed since last parsing
        debug && echo "File '$LIGHT_MAPPING_PATH' is more recent than '$AUTO_MAPPING_PATH'. Parsing '$LIGHT_MAPPING_PATH'."
        ~/hue-cli/parse_hue_mappings.sh $LIGHT_MAPPING_PATH $AUTO_MAPPING_PATH
    fi
fi

# -- Load light-aliases with their light numbers
debug && echo "Parsing light aliases from file '$LIGHT_MAPPING_PATH'"
while IFS='=' read light_alias lights_str; do
    LIGHT_ALIASES[$light_alias]=$lights_str
    debug && echo "Parsed light_alias '$light_alias'  and lights_str '$lights_str'"
done < $LIGHT_MAPPING_PATH

# light_nr, json
set_light_state() {
    error=$(echo $2 | curl -s -X PUT http://$HUE_BRIDGE_IP/api/$API_KEY/lights/$1/state \
    --data-binary @- | jq '.[0].error')
    if [ "$error" != "null" ]; then
        echo "Error while setting state of light $1:"
        echo "$error"
        return 1
    fi
    print && echo "Successfully set state of light $1."
    return 0
}

# Execute the instruction given as an argument. Instruction has the form a=b, where a is a list of light aliases and b is a list of properties
# to apply to the lights (both comma-separated). If b is empty, a will be parsed as the light alias list. If that fails, b will be
# assigned a's content and they will be interpreted as a list of properties.
# If a is empty a default list of light aliases will be used, specified in the light mappings. If no default is specified, use all
# lights from 1 to $LIGHT_NR. If b is empty and a does not contain properties, b will be assigned a default value (__default), or 'off' if none is configured.

execute_instruction() {
    declare -gA curr_instruction # Clear previous instruction
    LIGHT_LIST=() # Clear previous lights

    IFS='=' read light_aliases properties <<< $1 # Split instruction into lights and properties

    debug && echo "Executing instruction '$1'. Parsed light_aliases '$light_aliases' and properties '$properties'"

    if [ -v $light_aliases ]; then # Use default lights
        debug && echo "No light aliases. Using default lights '$DEFAULT_LIGHTS'."
        light_aliases=$DEFAULT_LIGHTS
    fi

    if [ -v $properties ]; then
        debug && echo "Empty properties. Trying to parse light_aliases as light aliases."
        try_parse_light_list "$light_aliases" # Try to parse first argument as lights
        if [ $? -ne 0 ]; then # If parsing of light-list was unsuccessful, operate on default (for now all) lights and try to parse as first argument as properties instead
            debug && echo "Failed to parse list of light aliases '$light_aliases'. Trying to parse as command instead, operating on default lights '$DEFAULT_LIGHTS'."
            properties=$light_aliases
            light_aliases=$DEFAULT_LIGHTS
        else # Parsing of lights was successful -> use default command
            debug && echo "Parsing of light aliases successful. No properties. Falling back to default '$DEFAULT_PROPERTIES'."
            properties=$DEFAULT_PROPERTIES
        fi
    fi

    # Check if light_aliases or properties are (still) empty, meaning that the defaults are empty; If so, fallback to all lights / off
    if [ -v $light_aliases ]; then
        debug && echo "Light aliases still empty. Falling back to using all lights (1 to $NR_LIGHTS)."
        LIGHT_LIST=($(seq 1 1 $NR_LIGHTS))
    elif [ ${#LIGHT_LIST[@]} -eq 0 ]; then # Avoid unnecessary double parsing of light_aliases
        debug && echo "Trying to parse light aliases."
        try_parse_light_list "$light_aliases" # TODO: add check
        if [ $? -ne 0 ]; then # If parsing of light-list was unsuccessful, operate on default (for now all) lights and try to parse as first argument as properties instead
            echo "Failed to parse list of light aliases '$light_aliases'."
            exit 1
        fi
        debug && echo "Successfully parsed light aliases."
    fi

    if [ -v $properties ]; then
        debug && echo "Properties still empty. Falling back to 'off'."
        properties=off
    fi

    debug && echo "Constructing associative array from properties."
    # Construct associative array from properties
    for val in ${properties//,/ }
    do
        case $val in
            "on")
            debug && echo "Adding 'on'=true."
            curr_instruction["on"]=true
            ;;
            "off")
            debug && echo "Adding 'on'=false."
            curr_instruction["on"]=false
            ;;
            b[0-9][0-9]*)
            debug && echo "Adding 'bri'=${val:1}."
            curr_instruction["bri"]=${val:1}
            ;;
            h[0-9][0-9]*)
            debug && echo "Adding 'hue'=${val:1}."
            curr_instruction["hue"]=${val:1}
            ;;
            s[0-9][0-9]*)
            debug && echo "Adding 'sat'=${val:1}."
            curr_instruction["sat"]=${val:1}
            ;;
            *)
            echo -n "Unknown property in command '$1': Expected 'on', 'off' or '@(s|h|b)[0-9]+', got '$val'"
            echo
            return 1;
            ;;
        esac
    done

    # Construct json from curr_instruction
    json_str="$(for key in "${!curr_instruction[@]}"; do
            printf '%s\0%s\0' "$key" "${curr_instruction[$key]}"
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

    debug && echo "json_str=$json_str"

    for light_nr in ${LIGHT_LIST[@]}
    do
        # TODO: check if light_nr is valid light number
        set_light_state $light_nr "$json_str"
    done
}

# Read commands
debug && echo "Loading commands"
while IFS=':' read name instructions; do
    debug && echo "COMMANDS[$name]=$instructions}"
    COMMANDS[$name]=$instructions
done < $COMMAND_PATH

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
    if [ -v $1 ]; then # Check if empty TODO: this should not be necessary here
        return
    fi
    # Check if nr already exists; if so, don't add it again. NOTE: quadratic time complexity
    for nr in $LIGHT_LIST
    do
        if [ "$1" -eq "$nr" ]; then
            debug && echo "Light $nr already present in LIGHT_LIST"
            return
        fi
    done
    # Nr not in list
    debug && echo "Light $1 not present in LIGHT_LIST. Adding it."
    LIGHT_LIST+=($1)
}

try_parse_light_list() {
    for light_alias in ${1//,/ }
    do
        debug && echo "light_alias = $light_alias"
        if [[ $light_alias =~ ^[0-9]+$ ]]; then # Light-Number
            debug && echo "Light alias is number."
            if (( 0 <= $light_alias && $light_alias  <= $NR_LIGHTS )); then
                add_light_nr_if_new $light_alias
                continue
            else
                return 1
            fi
        fi
        if [ -v LIGHT_ALIASES[$light_alias] ]; then # Light-alias
            debug && echo "Light alias is name. LIGHT_ALIASES[$light_alias]=${LIGHT_ALIASES[$light_alias]}"
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

arg1=$1
arg2=$2

# If both args are empty, fallback to __default.
if [ -v $arg1 ] && [ -v $arg2 ]; then
    debug && echo "No light aliases and properties. Falling back to default command '__default'."
    arg1=__default
fi

# Process command if first arg is command
if [[ -v COMMANDS[$arg1] ]]; then
    debug && echo "Executing command $arg1"
    # Instructions are split using ;
    command=${COMMANDS[$arg1]}
    for instruction in ${command//;/ }
    do
        debug && echo "Executing instruction $instruction"
        execute_instruction $instruction # TODO: check for errors
    done
    exit 0
else
    debug && echo "Did not recognize a command."
fi

# Convert the input into a command to be executed

# TODO: make this more intuitive / user-friendly by leaving out the equals-sign etc in the input (and then converting that input to a command here)
# For now, the commands will be expected to look exactly like the ones in the file

execute_instruction "$arg1=$arg2"

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
