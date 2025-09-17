#!/bin/bash

# Configuration
I2C_BUS=2
MUX_ADDR=0x77
SENSOR_ADDR=0x10

# Defaults
DEFAULT_CHANNEL=2
DEFAULT_READ_ATTEMPTS=3
DEFAULT_SENSITIVITY=40  # Integration Time in ms: 40, 80, 160, 320, 640, 1280

# Help
show_usage() {
    echo "Usage: $0 [channel] [samples] [sensitivity]"
    echo "  channel: 0-3 (default: ${DEFAULT_CHANNEL})"
    echo "  samples: 1-20 (default: ${DEFAULT_READ_ATTEMPTS})"
    echo "  sensitivity: 40/80/160/320/640/1280 ms (default: ${DEFAULT_SENSITIVITY}ms)"
    echo "Examples:"
    echo "  $0                 # channel 1, 3 samples, 40ms"
    echo "  $0 2               # channel 2, 3 samples, 40ms"
    echo "  $0 2 5             # channel 2, 5 samples, 40ms"
    echo "  $0 2 5 320         # channel 2, 5 samples, 320ms"
    exit 1
}

validate_number() {
    local value=$1
    local min=$2
    local max=$3
    local name=$4

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: $name must be a number"
        show_usage
    fi

    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        echo "Error: $name must be between $min and $max"
        show_usage
    fi
}

error_exit() {
    echo "[ERROR] $1" >&2
    echo "FAIL"
    exit 1
}

check_i2c_tools() {
    if ! command -v i2cset &> /dev/null || ! command -v i2cget &> /dev/null; then
        error_exit "i2c-tools not found. Please run: sudo apt-get install i2c-tools"
    fi
}

setup_sensor() {
    local channel=$1
    local sensitivity=${2:-$DEFAULT_SENSITIVITY}

    mux_ctrl_val=$((0x04 + channel))
    if ! i2cset -y $I2C_BUS $MUX_ADDR $mux_ctrl_val 2>/dev/null; then
        error_exit "Failed to set MUX channel. Check I2C connection."
    fi
    sleep 0.01

    local config_word=0x0000
    case "$sensitivity" in
        40)   config_word=0x0000 ;;
        80)   config_word=0x0010 ;;
        160)  config_word=0x0020 ;;
        320)  config_word=0x0030 ;;
        640)  config_word=0x0040 ;;
        1280) config_word=0x0050 ;;
        *)
            echo "Error: Invalid sensitivity. Only 40, 80, 160, 320, 640, 1280 allowed."
            exit 1
            ;;
    esac

    if ! i2cset -y $I2C_BUS $SENSOR_ADDR 0x00 $(printf "0x%02x" $((config_word & 0xFF))) $(printf "0x%02x" $((config_word >> 8))) i 2>/dev/null; then
        error_exit "Failed to initialize sensor. Check connection."
    fi
    sleep 0.05
}

read_and_convert() {
    local reg=$1
    local data=$(i2cget -y $I2C_BUS $SENSOR_ADDR $reg w | sed 's/0x//')

    if [ ${#data} -ne 4 ]; then
        echo "0"
        return
    fi

    local swapped=${data:2:2}${data:0:2}
    echo $((0x$swapped))
}

read_sensor_data() {
    local red=$(read_and_convert 0x08)
    local green=$(read_and_convert 0x09)
    local blue=$(read_and_convert 0x0A)
    local white=$(read_and_convert 0x0B)
    echo "$red $green $blue $white"
}

main() {
    local channel=$DEFAULT_CHANNEL
    local read_attempts=$DEFAULT_READ_ATTEMPTS
    local sensitivity=$DEFAULT_SENSITIVITY

    if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        show_usage
    fi

    if [ $# -ge 1 ]; then
        validate_number "$1" 0 3 "Channel"
        channel=$1
    fi

    if [ $# -ge 2 ]; then
        validate_number "$2" 1 20 "Sample count"
        read_attempts=$2
    fi

    if [ $# -ge 3 ]; then
        validate_number "$3" 40 1280 "Sensitivity"
        if ! [[ "$3" =~ ^(40|80|160|320|640|1280)$ ]]; then
            echo "Error: Sensitivity must be one of 40, 80, 160, 320, 640, 1280"
            show_usage
        fi
        sensitivity=$3
    fi

    if [ $# -gt 3 ]; then
        echo "Note: Only up to 3 parameters are accepted. Extra parameters will be ignored."
    fi

    check_i2c_tools
    setup_sensor "$channel" "$sensitivity"

    declare -a readings

    for ((i=0; i<read_attempts; i++)); do
        if data=$(read_sensor_data); then
            readings[i]="$data"
            sleep 0.05
        else
            error_exit "Failed to read sensor"
        fi
    done

    local red_sum=0 green_sum=0 blue_sum=0 white_sum=0
    for reading in "${readings[@]}"; do
        IFS=' ' read -ra vals <<< "$reading"
        red_sum=$((red_sum + vals[0]))
        green_sum=$((green_sum + vals[1]))
        blue_sum=$((blue_sum + vals[2]))
        white_sum=$((white_sum + vals[3]))
    done

    local red_avg=$((red_sum/read_attempts))
    local green_avg=$((green_sum/read_attempts))
    local blue_avg=$((blue_sum/read_attempts))
    local white_avg=$((white_sum/read_attempts))

    echo -e "===== Average RGBW Values ====="
    printf "Red:   %-5d\n" $red_avg
    printf "Green: %-5d\n" $green_avg
    printf "Blue:  %-5d\n" $blue_avg
    printf "White: %-5d\n" $white_avg

    # Verify that the read data is complete and valid
    if [ "${#readings[@]}" -eq "$read_attempts" ]; then
        valid=1
        for reading in "${readings[@]}"; do
            IFS=' ' read -ra vals <<< "$reading"
            if [ "${#vals[@]}" -ne 4 ]; then
                valid=0
                break
            fi
        done
        if [ "$valid" -eq 1 ]; then
            echo "PASS"
            exit 0
        fi
    fi

    echo "FAIL"
    exit 1
}

main "$@"
