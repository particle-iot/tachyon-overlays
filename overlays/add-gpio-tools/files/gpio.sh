#!/bin/bash

# GPIO control script with extended functionality
# Commands: set, get, list, init, getall, help

GPIO_BASE=336  # Offset for GPIO numbers

# Define GPIO group mappings
declare -A GPIO_GROUPS=(
    ["display_cam"]="68 15 107"
    ["MCU"]="20 21 46 63"
    ["40pin"]="144 145 146 147 24 61 6 19 33 44 36 37 32 18 158 106 78 62 165 166"
    ["power"]="7"
)

# Define GPIO default direction and value for each pin
declare -A GPIO_DEFAULTS=(
    ["display_cam_68"]="out 0"
    ["display_cam_15"]="out 0"
    ["display_cam_107"]="out 1"
    ["MCU_20"]="out 0"
    ["MCU_21"]="out 0"
    ["MCU_46"]="out 0"
    ["MCU_63"]="out 0"
    ["40pin_144"]="in"
    ["40pin_145"]="in"
    ["40pin_146"]="in"
    ["40pin_147"]="in"
    ["40pin_24"]="in"
    ["40pin_61"]="in"
    ["40pin_6"]="in"
    ["40pin_19"]="in"
    ["40pin_33"]="in"
    ["40pin_44"]="in"
    ["40pin_36"]="in"
    ["40pin_37"]="in"
    ["40pin_32"]="in"
    ["40pin_18"]="in"
    ["40pin_158"]="in"
    ["40pin_106"]="in"
    ["40pin_78"]="in"
    ["40pin_62"]="in"
    ["40pin_165"]="in"
    ["40pin_166"]="in"
    ["power_7"]="out 1"
)

# Function to display help
print_help() {
    echo "GPIO Control Script"
    echo "Usage: $0 {set|get|list|init|getall|help}"
    echo
    echo "Commands:"
    echo "  set [gpio number] [out|in] [value]   Set a GPIO pin direction and value."
    echo "                                       Example: $0 set 54 out 1"
    echo
    echo "  get [gpio number]                    Get the current configuration of a GPIO pin."
    echo "                                       Example: $0 get 54"
    echo
    echo "  list                                 List all exported GPIO pins."
    echo "                                       Example: $0 list"
    echo
    echo "  init [group name]                    Initialize all GPIO pins in a group with default settings."
    echo "                                       Example: $0 init Display_Cam"
    echo
    echo "  getall                               List all GPIO pins with group, direction, and value."
    echo "                                       Example: $0 getall"
    echo
    echo "  help                                 Display this help message."
    echo "                                       Example: $0 help"
    echo
    exit 0
}

# Function to set GPIO direction and value
set_gpio() {
    GPIO=$1
    GPIO_NUMBER=$(($GPIO + $GPIO_BASE))
    DIRECTION=$2
    GPIO_VALUE=$3

    # Check if GPIO is already exported
    if [ ! -d /sys/class/gpio/gpio$GPIO_NUMBER ]; then
        echo $GPIO_NUMBER > /sys/class/gpio/export
        if [ $? -ne 0 ]; then
            echo "Error: Failed to export GPIO $GPIO_NUMBER."
            return 1
        fi
    fi

    # Set direction
    echo $DIRECTION > /sys/class/gpio/gpio$GPIO_NUMBER/direction
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set GPIO $GPIO_NUMBER direction to $DIRECTION."
        return 1
    fi

    # Set value if direction is "out"
    if [[ $DIRECTION == "out" ]]; then
        echo $GPIO_VALUE > /sys/class/gpio/gpio$GPIO_NUMBER/value
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set GPIO $GPIO_NUMBER value to $GPIO_VALUE."
            return 1
        fi
    fi

    # Unexport the GPIO to release it from sysfs control
    unexport_gpio $GPIO
    if [ $? -ne 0 ]; then
        echo "Error: Failed to unexport GPIO $GPIO."
        ERRORS=$((ERRORS + 1))
    fi

    echo "GPIO $(($GPIO_NUMBER - $GPIO_BASE)) configured as $DIRECTION with value $GPIO_VALUE."
    return 0
}

# Unexport the given GPIO
unexport_gpio() {
    GPIO_NUMBER=$(($1 + $GPIO_BASE))

    # Check if GPIO is already exported
    if [ -d /sys/class/gpio/gpio$GPIO_NUMBER ]; then
        echo $GPIO_NUMBER > /sys/class/gpio/unexport
        if [ $? -ne 0 ]; then
            echo "Error: Failed to unexport GPIO $GPIO_NUMBER."
            return 1
        fi
        #echo "GPIO $(($GPIO_NUMBER - $GPIO_BASE)) unexported"
    fi
    return 0
}

# Function to initialize GPIOs for a group
init_gpio_group() {
    GROUP=$1

    if [ -z "${GPIO_GROUPS[$GROUP]}" ]; then
        echo "Error: GPIO group $GROUP not found."
        return 1
    fi

    echo "Initializing GPIO group: $GROUP"

    ERRORS=0
    for GPIO in ${GPIO_GROUPS[$GROUP]}; do
        DEFAULT_KEY="${GROUP}_${GPIO}"
        if [ -n "${GPIO_DEFAULTS[$DEFAULT_KEY]}" ]; then
            DIRECTION=$(echo ${GPIO_DEFAULTS[$DEFAULT_KEY]} | cut -d' ' -f1)
            VALUE=$(echo ${GPIO_DEFAULTS[$DEFAULT_KEY]} | cut -d' ' -f2)

            # Attempt to set the GPIO
            set_gpio $GPIO $DIRECTION $VALUE
            if [ $? -ne 0 ]; then
                echo "Error: Failed to initialize GPIO $GPIO ($DEFAULT_KEY)."
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "Warning: No defaults found for $DEFAULT_KEY. Skipping."
        fi
    done

    if [ $ERRORS -ne 0 ]; then
        echo "Initialization completed with $ERRORS errors in group $GROUP."
        return 1
    else
        echo "Initialization completed successfully for group $GROUP."
        return 0
    fi
}

# Function to get GPIO value
get_gpio() {
    GPIO_NUMBER=$(($1 + $GPIO_BASE))

    if [ ! -d /sys/class/gpio/gpio$GPIO_NUMBER ]; then
        echo "Error: GPIO $1 is not exported."
        return 1
    fi

    VALUE=$(cat /sys/class/gpio/gpio$GPIO_NUMBER/value)
    DIRECTION=$(cat /sys/class/gpio/gpio$GPIO_NUMBER/direction)
    echo "GPIO $1 is configured as $DIRECTION with value $VALUE."
    return 0
}

# Function to list all GPIOs
list_gpios() {
    echo "Listing all exported GPIOs:"
    for GPIO_PATH in /sys/class/gpio/gpio*; do
        GPIO_NUMBER=${GPIO_PATH##*gpio}
        GPIO_OFFSET=$(($GPIO_NUMBER - $GPIO_BASE))
        if [ $GPIO_OFFSET -ge 0 ]; then
            DIRECTION=$(cat $GPIO_PATH/direction)
            VALUE=$(cat $GPIO_PATH/value)
            echo "GPIO $GPIO_OFFSET: direction=$DIRECTION, value=$VALUE"
        fi
    done
}

# Function to get all GPIOs with group information
getall_gpios() {
    echo "Listing all GPIOs with group, direction, and value:"
    for GROUP in "${!GPIO_GROUPS[@]}"; do
        for GPIO in ${GPIO_GROUPS[$GROUP]}; do
            GPIO_NUMBER=$(($GPIO + $GPIO_BASE))
            if [ -d /sys/class/gpio/gpio$GPIO_NUMBER ]; then
                DIRECTION=$(cat /sys/class/gpio/gpio$GPIO_NUMBER/direction)
                VALUE=$(cat /sys/class/gpio/gpio$GPIO_NUMBER/value)
                echo "$GROUP    GPIO_$GPIO    $DIRECTION    $VALUE"
            else
                echo "$GROUP    GPIO_$GPIO    not exported"
            fi
        done
    done
}

# Main command dispatch
COMMAND=$1
shift

case "$COMMAND" in
    set)
        if [ $# -lt 2 ]; then
            echo "Usage: $0 set [gpio number] [out|in] [value if out: 0|1]"
            exit 1
        fi
        set_gpio "$@"
        ;;
    get)
        if [ $# -lt 1 ]; then
            echo "Usage: $0 get [gpio number]"
            exit 1
        fi
        get_gpio "$@"
        ;;
    list)
        list_gpios
        ;;
    init)
        if [ $# -lt 1 ]; then
            echo "Usage: $0 init [group name]"
            exit 1
        fi
        init_gpio_group "$@"
        ;;
    getall)
        getall_gpios
        ;;
    help|""|*)
        print_help
        ;;
esac
