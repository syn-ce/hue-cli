A tiny CLI for interacting with smart lights through your Philips Hue bridge.
Define your own light aliases and commands and execute them directly from the command line.

## Overview

[Getting started](#getting-started) <br>
[Running the script](#running-the-script) <br>
[Light mappings](#light-mappings) <br>
[Commands](#commands) <br>
&nbsp;&nbsp;&nbsp;&nbsp; [\_\_default command](#__default-command) <br>
&nbsp;&nbsp;&nbsp;&nbsp; [Instructions](#instructions) <br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; [Properties](#properties) <br>
&nbsp;&nbsp;&nbsp;&nbsp; [Example commands](#example-commands) <br>
[Configuration](#configuration) <br>
&nbsp;&nbsp;&nbsp;&nbsp; [Example config](#example-config) <br>

## Getting started

You will first need to obtain your bridge's IP address and an API-key. In case you don't already have these, you can follow [this brief introduction](https://developers.meethue.com/develop/get-started-2/).

If you want to get started without making any changes to the code you can simply download the `hue-cli` folder and place it in your home directory. After that, download `hue.sh` and make it executable by running `chhmod +x hue.sh`. In case you don't want to keep the `.sh` file ending, remove it by running `mv hue.sh hue`. Now place the file in a directory in your PATH (e.g. /usr/bin/) to be able to run it from anywhere. Just make sure you don't already have a command called `hue(.sh)`.

Before running for the first time you'll want to have a look at the [configuration](#configuration) and the [light mappings](#light-mappings).

## Running the script

The script can be run in one of the following ways:

1. `hue` executes the [`__default` command](#__default-command)
2. `hue [LIGHT_LIST] [PROPERTIES]` sets properties for lights
3. `hue [LIGHT_LIST]` sets [default properties](#default_properties) for lights in list
4. `hue [PROPERTIES]` sets properties for [default lights](#default_lights)

## Light mappings

By default, your hue bridge assigns numbers from $1$ to $n$ to your lights. [Think of a name] allows you to create aliases for your lights, in case you would like to work with more descriptive names. These "mappings" are specified in `hue-cli/hue_light_mappings` (default).
They have the form `name=LIGHT_LIST` (note the absence of whitespace), where `name` is the name of the lights specified in `LIGHT_LIST`. `LIGHT_LIST` is a comma-separated (**no whitespace**) list of an arbitrary number of lights, specified by their numbers or by aliases.
An example will clear things up: Suppose you had one light (numbered 1) in your living room and two lights (numbered 2,3) in your bathroom. If light number 2 was associated with a mirror, your `hue_light_mappings` might look like this:

```
house=bath,living_room
mirror=3
bath=mirror,2
living_room=1
```

Note that you can arbitrarily define aliases for other aliases, allowing you two group your lights together however you want. The only limitation is that the resulting graph be a **DAG (directed acyclic graph)**, that is, it shall not contain any circles.
The following would therefore **not** be a valid mapping:

```
house=bath,living_room
mirror=3,house
bath=mirror,2,house
living_room=1
```

The aliases cannot be numbers themselves.
If for some reason you want to define empty aliases, you can do so (`empty_alias=`).

## Commands

You can create aliases for commands and specify them in the [command file](#command_path). These commands can then be run directly from the command line by running `hue command_name`. A command has the form `command_name:INSTRUCTION_LIST`, where `command_name` is the name of the command and `INSTRUCTION_LIST` is a `;`-delimited list of [instructions](#instructions).

Example of a `hue_commands` file:

```
__default:1=off;2=h20,on
night:1,2,3=h50,b70,s100,on
```

#### \_\_default command

Notice the `__default` command above? When calling the script without specifying any arguments, this command will be executed. Just like any other command, it consists of a list of `;`-delimited instructions.

Calling `hue` is therefore equivalent to calling `hue __default`.

### Instructions

An instruction has the form `LIGHT_LIST=PROPERTIES` where `LIGHT_LIST` is a list of lights (aliases and/or numbers) and `PROPERTIES` defines a comma-separated (no whitespace) list of [properties](#properties) to apply to these lights.

Instructions behave a bit special when either of the above is empty. In particular, an instruction will be parsed as follows:
If both `LIGHT_LIST` and `PROPERTIES` are empty, fall back to the [defaults](#default_lights). When only `LIGHT_LIST` is empty, fall back to its default. However, when only `PROPERTIES` is empty, the script will try to parse the `LIGHT_LIST` as a list of lights; If this succeeds, `PROPERTIES` falls back to its default value. If the parsing as a light list fails, the script will try to parse the initial `LIGHT_LIST` value as `PROPERTIES`, i.e. a list of properties. If that works, `LIGHT_LIST` falls back to its default. If it does not succeed, the script exits on error. This rather odd seeming behavior has its roots in the fact that the script can be called in [four ways](#running-the-script) with varying order of arguments.

#### Properties

There are currently 4 supported properties which can be used to build an instruction. All of these directly refer to fields in the json of a light in the offical hue api for your bridge:

-   `on` sets on=true
-   `off` sets on=false
-   `b=X` sets the bri-value
-   `h=X` sets the hue-value
-   `s=X` sets the sat-value

### Example commands

Suppose the [defaults](#default_lights) in the [config file](#configuration) looked like this:

```
...
DEFAULT_LIGHTS=1,3
DEFAULT_PROPERTIES=off,b=20
...
```

Then these commands would do the following:

`night:1,3=h50,b70,s100,on;2=off` - sets hue=50, bri=70, s100 and on=true for lights 1 and 3, sets on=false for light 2

`shutdown:=off` - sets on=false [default lights](#default_lights), i.e. turns off default lights

`def:=` - sets [default properties](#default_properties) for [default_lights](#default_lights)

`cozy:=b10,1=off` - sets bri=10 for default lights and turns light 1 off

## Configuration

The main shell script will require a config file (by default it expects it to be `~/hue-cli/hue_config`).
This config file will be sourced at startup and defines some variables which will be used throughout the script. All have the form `name=value` without whitespace:

##### `HUE_BRIDGE_IP`

Your bridges IP address.

##### `API_KEY`

The api key obtained by following [this brief introduction](https://developers.meethue.com/develop/get-started-2/).

##### `NR_LIGHTS`

The number of lights you have connected to your hue bridge. It will be assumed that the lights are numbered 1 to n.

##### `LIGHT_MAPPING_PATH`

Path to the file containing the [light mappings](#light-mappings).

##### `AUTO_MAPPING_PATH`

Path to the file to which the automatically generated mappings will be written. Whenever the main script is run, it will check whether the user's light mappings have been updated since the [light mapping file](#light_mapping_path) file has last been updated. If it has, then the script will call `~/hue-cli/parse_hue_mappings.sh` which will parse the mappings specified in the [light mapping file](#light_mapping_pathhue-clihue_light_mappings) and write the generated output to the file specified here. This generated file will contain the same mappings as the file specified by the user, but the lists on the right hand side of `name=LIGHT_LIST` will only contain numbers, making it much more comfortable to work wit, making it much more comfortable to work with in code.

##### `COMMAND_PATH`

All [commands](#commands) are defined in this file.

##### `DEFAULT_LIGHTS`

When executing an instruction which does not specify a light list, this list of lights will be used. May contain light numbers and/or aliases. When left empty, the script will default to all lights (that is, it will use `NR_LIGHTS` and act on all 1 to `NR_LIGHTS` lights). For more information see [Instructions](#instructions).

##### `DEFAULT_PROPERTIES`

When executing an instruction which does not specify a list of properties, this list of properties will be used. When left empty, the script will default to `off`. That is, the properties will be set to `off`, meaning the lights acted upon will simply be turned off. That is, the list of properties will be set to `off`, meaning the lights acted upon will simply be turned off.

##### `PRINT`

Optional. When specified, the numbers of the lights affected by the executed instruction will be printed. The value will be ignored.

##### `DEBUG`

Optional. When specified, more detailed information about the program's execution will be output. Only use this when trying to debug the script.

### Example config

```
HUE_BRIDGE_IP=XXX.XXX.X.XXX
API_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
NR_LIGHTS=3
LIGHT_MAPPING_PATH=~/hue-cli/hue_light_mappings
AUTO_MAPPING_PATH=~/hue-cli/generated/hue_auto_mappings
COMMAND_PATH=~/hue-cli/hue_commands
DEFAULT_LIGHTS= # Will fallback to all lights
DEFAULT_PROPERTIES= # Will fallback to 'off'
PRINT=
#DEBUG= # Commented out
```
