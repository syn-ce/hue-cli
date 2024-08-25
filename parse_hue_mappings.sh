#! /bin/bash

# Reads the light mappings from aliases to aliases and light numbers defined in $1 (house=living_room,bath,1)
# and processes them into a config $2 containing mappings from aliases to their lights (house=1,2,3,6).

declare -A word2nums
declare -A word2arr_str
declare -A stack

# Process the comma-separated string value
process_arr_str() {
    local key=$1
    #echo "${word2nums[$key]}"
    # Key has already been processed
    if [[ -v "stack[$key]" ]]; then
        # Found circle
        echo "Found circle!"
        return 1
    fi

    stack["$key"]="" # Add to stack
    word2nums["$key"]="" # Set default value for key

    # Set IFS to a comma and iterate over the string
    #IFS=','
    local arr_str="${word2arr_str[$key]}"
    arr_str=${arr_str//,/ }

    # Process every number and string (name) in the current array of light-aliases and -numbers
    for val in $arr_str
    do
        # If val is a a number, simply add it to the key's list of light-nums
        if [[ $val =~ ^[0-9]+$ ]]; then
            word2nums["$key"]+="$val "
        else
            # Value is another alias
            if ! [[ -v "word2nums[$val]" ]]; then # Process alias if it has not been processed yet
                process_arr_str $val
                if [ $? -ne 0 ]; then # Check if successfull
                    return 1
                fi
                unset 'stack[$val]' # Pop from stack
            elif [[ -v "stack[$val]" ]]; then # Mapping has to be DAG; No cycles allowed
                echo "Found circle with $val"
                return 1
            fi

            # Add nrs of alias to this one
            # NOTE: quadratic time complexity
            for nr in ${word2nums[$val]}
            do
                # Add nr if it's not in key's list already
                if ! echo " ${word2nums[$key]}" | grep -q " $nr "
                then
                    word2nums["$key"]+="$nr "
                fi
            done
        fi
    done
}

# Check args
if [ -z $1 ]; then
    echo "Require first argument to be the full path to the file in which the mappings are defined, but no first argument was provided."
    exit 1
fi

if [ -z $2 ]; then
    echo "Require second argument to be the full path to the file to which to write the generated mappings to (AUTO_MAPPING_PATH), but no second argument was provided."
    exit 1
fi

LIGHT_MAPPING_PATH=$1
AUTO_MAPPING_PATH=$2

# Read aliases with their respective array
while IFS='=' read key arr_str; do
    word2arr_str[$key]="$arr_str"
done < $LIGHT_MAPPING_PATH


# Process all keys
for key in "${!word2arr_str[@]}"
do
    # Avoid processing already processed key (has been processed by recursive call)
    if ! [[ -v "word2nums[$key]" ]]; then
        process_arr_str $key
        if [ $? -ne 0 ]; then
            echo "Failed to process config."
            exit 1
        fi
        unset 'stack[$key]' # Pop from stack
    fi
    # Remove trailing spaces
    if [ ! -z "${word2nums[$key]}" ]; then
        word2nums[$key]="${word2nums[$key]::-1}"
    fi
done

# Clear config-file
true > $AUTO_MAPPING_PATH
# Sort and write everything into config-file
for key in "${!word2nums[@]}"
do
    # Sort
    word2nums[$key]=$(echo "${word2nums[$key]}" | tr ' ' '\n' | sort -n | paste -sd ' ')
    # Append to file
    echo "$key=${word2nums[$key]}" >> $AUTO_MAPPING_PATH
done
