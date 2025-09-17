#!/bin/bash

declare -a VOLTAGE_MATRIX=()
PRINT_MATRIX=true

# GPIO list
GPIO_LIST=(44 144 33 35 34 61 9 8 59 58 24 56 57 166 165 158 145 106 78 19 18 37 36 62 147 146 6 32)

# GPIO to ADC mapping (format: gpio:addr:channel)
GPIO_ADC_MAP=(
    "44:0x4a:0" "144:0x4a:1" "33:0x4a:2" "35:0x4a:3"
    "34:0x4a:4" "61:0x4a:5" "9:0x4a:6" "8:0x4a:7"
    "59:0x48:0" "58:0x48:1" "24:0x48:2" "56:0x48:3"
    "57:0x48:4" "166:0x48:5" "165:0x48:6" "158:0x48:7"
    "145:0x4b:0" "106:0x4b:1" "78:0x4b:2" "19:0x4b:3"
    "18:0x4b:4" "37:0x4b:5" "36:0x4b:6" "62:0x4b:7"
    "147:0x49:4" "146:0x49:5" "6:0x49:6" "32:0x49:7"
)

THRESHOLD=2.5 # Voltage threshold for high/low level detection
declare -A ADC_RESULT

# Initialize all GPIOs as output low
init_gpios() {
    # level shifter
    /opt/particle/tests/control-gpio.sh "7" out 1 > /dev/null
    for gpio_init in "${GPIO_LIST[@]}"; do
        /opt/particle/tests/control-gpio.sh "$gpio_init" out 0 > /dev/null
    done
}

# Set single GPIO high and others low
set_single_gpio_high() {
    local target_gpio=$1
    for gpio_set in "${GPIO_LIST[@]}"; do
        if [[ "$gpio_set" -eq "$target_gpio" ]]; then
            /opt/particle/tests/control-gpio.sh "$gpio_set" out 1 > /dev/null
        else
            /opt/particle/tests/control-gpio.sh "$gpio_set" out 0 > /dev/null
        fi
    done
}

# Read all ADC values and store in map
read_adc_values() {
    ADC_RESULT=()
    local adc_addresses=("0x4a" "0x48" "0x4b" "0x49")

    for adc_addr in "${adc_addresses[@]}"; do
        while IFS= read -r line; do
            if [[ "$line" =~ Channel[[:space:]]([0-7]):.*Voltage=([0-9]+\.[0-9]+) ]]; then
                ADC_RESULT["$adc_addr:${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi
        done < <(/opt/particle/tests/read-test-board 0 "$adc_addr" 2>/dev/null)
    done
}

# Verify if GPIO setting is correct
check_result() {
    local target_gpio=$1
    local result="pass"

    # Check target GPIO
    local expected_key=""
    for map_entry in "${GPIO_ADC_MAP[@]}"; do
        IFS=: read -r map_gpio map_addr map_ch <<< "$map_entry"
        if [[ "$map_gpio" == "$target_gpio" ]]; then
            expected_key="$map_addr:$map_ch"
            break
        fi
    done

    local target_value="${ADC_RESULT[$expected_key]:-0}"
    local target_is_high=$(awk -v v="$target_value" -v t="$THRESHOLD" 'BEGIN { print (v > t) }')

    if (( target_is_high != 1 )); then
        result="fail"
    fi

    # Check other GPIOs
    for map_entry in "${GPIO_ADC_MAP[@]}"; do
        IFS=: read -r map_gpio map_addr map_ch <<< "$map_entry"
        [[ "$map_gpio" == "$target_gpio" ]] && continue

        local key="$map_addr:$map_ch"
        local value="${ADC_RESULT[$key]:-0}"
        local is_high=$(awk -v v="$value" -v t="$THRESHOLD" 'BEGIN { print (v > t) }')

        if (( is_high == 1 )); then
            result="fail"
        fi
    done

    [[ "$result" == "pass" ]]
}

# Save results to matrix
save_result_array() {
    local -a voltages
    for ordered_gpio in "${GPIO_LIST[@]}"; do
        for map_entry in "${GPIO_ADC_MAP[@]}"; do
            IFS=: read -r map_gpio map_addr map_ch <<< "$map_entry"
            if [[ "$map_gpio" == "$ordered_gpio" ]]; then
                local key="$map_addr:$map_ch"
                voltages+=("$(printf "%.4f" "${ADC_RESULT[$key]:-0}")")
                break
            fi
        done
    done
    VOLTAGE_MATRIX+=("$(printf '[%s]' "$(IFS=,; echo "${voltages[*]}")")")
}

main() {
    # parse param
    for arg in "$@"; do
        if [[ "$arg" == "--no-matrix" ]]; then
            PRINT_MATRIX=false
        fi
    done

    init_gpios
    local pass_count=0
    local fail_count=0
    local failed_gpios=()

    echo "Starting GPIO tests..."

    for current_gpio in "${GPIO_LIST[@]}"; do
        echo -n "Testing GPIO $current_gpio..."
        set_single_gpio_high "$current_gpio"
        read_adc_values
        save_result_array
        if check_result "$current_gpio"; then
            echo " PASS"
            ((pass_count++))
        else
            echo " FAIL"
            ((fail_count++))
            failed_gpios+=("$current_gpio")
            echo "FAIL"
            exit 1
        fi
    done

    init_gpios

    if [[ "$PRINT_MATRIX" == true ]]; then
        echo -e "\n==== ADC Voltage Matrix for All GPIO High/Low Tests ===="
        printf '%s\n' "${VOLTAGE_MATRIX[@]}"
    fi

    echo -e "\n==== Final Summary ===="
    echo "Passed: $pass_count"
    echo "Failed: $fail_count"
    if (( fail_count > 0 )); then
        echo "Failed GPIOs: ${failed_gpios[*]}"
        echo "FAIL"
        exit 1
    else
        echo "PASS"
        exit 0
    fi
}

main "$@"
