# shellcheck shell=bash

__hardware_gstreamer_test() {
    local temp
    temp="$(mktemp tmp.XXXXXXXXXX.jpg)"

    if gst-launch-1.0 v4l2src "device=/dev/$RSETUP_MENU_SELECTED" io-mode=4 ! \
                      videoconvert ! \
                      video/x-raw,format=UYVY,width=1920,height=1080 ! \
                      jpegenc ! \
                      multifilesink "location=$temp"
    then
        msgbox "Test image is saved at $temp."
    else
        rm -f "$temp"
        msgbox "Unable to capture an image with $RSETUP_MENU_SELECTED device.
Please check if you have the required libraries installed."
    fi
}

__hardware_video() {
    menu_init
    for i in /dev/video*
    do
        menu_add __hardware_gstreamer_test "$(basename "$i")"
    done
    menu_emptymsg "No supported devices is detected.

Please make sure they are enabled first."
    menu_show "Take a test image with the selected video capture device:"
}

__hardware_gpio_leds() {
    checklist_init

    for i in /sys/bus/platform/drivers/leds-gpio/leds/leds/*
    do
        if [[ -f "$i/trigger" ]]
        then
            checklist_add "$(basename "$i") [$(sed -E "s/.*\[(.*)\].*/\1/" "$i/trigger")]" "OFF"
        fi
    done
    checklist_emptymsg "No supported devices is detected.

Please make sure they are enabled first."
    if ! checklist_show "Below are the available LEDs and their triggers.
Select any to update their trigger." || (( ${#RSETUP_CHECKLIST_STATE_NEW[@]} == 0 ))
    then
        return
    fi

    local triggers
    read -r -a triggers <<< "$(sed "s/\[//;s/\]//" "$(find -L /sys/bus/platform/drivers/leds-gpio/leds/leds/ -mindepth 2 -maxdepth 2 -name 'trigger' 2> /dev/null | head -1)")"

    radiolist_init
    for i in "${triggers[@]}"
    do
        radiolist_add "$i" "OFF"
    done
    if radiolist_show "Please select the new trigger:" && (( ${#RSETUP_RADIOLIST_STATE_NEW[@]} > 0 ))
    then
        for i in "${RSETUP_CHECKLIST_STATE_NEW[@]}"
        do
            read -r -a i <<< "$(checklist_getitem "$i")"
            radiolist_getitem "${RSETUP_RADIOLIST_STATE_NEW[0]}" > "/sys/bus/platform/drivers/leds-gpio/leds/leds/${i[0]}/trigger"
        done
    fi

    msgbox "LED trigger has been updated."
}

__hardware_thermal() {
    radiolist_init

    local current_policy available_policies
    current_policy="$(cat /sys/class/thermal/thermal_zone0/policy)"
    mapfile -t available_policies < <(sed -E -e "s/ $//g" -e "s/ /\n/g" /sys/class/thermal/thermal_zone0/available_policies)
    for i in "${available_policies[@]}"
    do
        if [[ "$i" == "$current_policy" ]]
        then
            radiolist_add "$i" "ON"
        else
            radiolist_add "$i" "OFF"
        fi
    done
    radiolist_emptymsg "No thermal governor is available."

    if ! radiolist_show "Please select the thermal governor.
Recommendation: fanless or DC fan => power_allocator | PWM fan => step_wise/fair_share" || (( ${#RSETUP_RADIOLIST_STATE_NEW[@]} == 0 ))
    then
        return
    fi

    set_thermal_governor "$(radiolist_getitem "${RSETUP_RADIOLIST_STATE_NEW[0]}")"

    msgbox "Thermal governor has been updated."
}

__hardware_rgb_leds() {
    :
}

__hardware_dsi_mirror() {
    local active_monitors=() dsi_monitors=() external_monitors=()
    mapfile -t active_monitors < <(xrandr --listactivemonitors | tail -n +2 | awk '{print $4}')
    for i in "${active_monitors[@]}"
    do
        if [[ "$i" =~ "DSI" ]]
        then
            dsi_monitors+=( "$i" )
        else
            external_monitors+=( "$i" )
        fi
    done

    if ! (( ${#dsi_monitors[@]} ))
    then
        msgbox "No active DSI display is found.
Please check if the overlay is enabled, and the screen is connected and powered on."
        return
    fi

    if ! (( ${#external_monitors[@]} ))
    then
        msgbox "No external display is found.
Please check if the screen is connected and powered on."
        return
    fi

    local selected_dsi="${dsi_monitors[0]}" selected_external=( "${external_monitors[0]}" )

    if (( ${#dsi_monitors[@]} > 1 ))
    then
        radiolist_init
        for i in "${dsi_monitors[@]}"
        do
            radiolist_add "$i" "OFF"
        done
        if ! radiolist_show "Please select the DSI monitor to be mirrored:" || (( ${#RSETUP_RADIOLIST_STATE_NEW[@]} == 0 ))
        then
            return
        fi
        selected_dsi="$(radiolist_getitem "${RSETUP_RADIOLIST_STATE_NEW[0]}")"
    fi

    if (( ${#external_monitors[@]} > 1 ))
    then
        checklist_init
        for i in "${external_monitors[@]}"
        do
            checklist_add "$i" "OFF"
        done
        if ! checklist_show "Please select external monitors to mirror the DSI monitor:" || (( ${#RSETUP_CHECKLIST_STATE_NEW[@]} == 0 ))
        then
            return
        fi
        selected_external=()
        for i in "${RSETUP_CHECKLIST_STATE_NEW[@]}"
        do
            selected_external+=( "$(checklist_getitem "$i")" )
        done
    fi

    local dsi_res dsi_native_res_x dsi_native_res_y
    dsi_res="$(tail -n 1 "/sys/devices/platform/display-subsystem/drm/card0/card0-$selected_dsi/modes")"
    dsi_native_res_x="$(cut -d "x" -f 1 <<< "$dsi_res")"
    dsi_native_res_y="$(cut -d "x" -f 2 <<< "$dsi_res")"

    local xrandr_cmd=(
        xrandr
        --output "$selected_dsi"
        --auto
        --primary
    )

    if (( dsi_native_res_x < dsi_native_res_y ))
    then
        xrandr_cmd+=( --rotate left )
        dsi_res="${dsi_native_res_y}x${dsi_native_res_x}"
    fi
    
    for i in "${selected_external[@]}"
    do
        xrandr_cmd+=( --output "$i" )
    done
        xrandr_cmd+=(
            --auto
            --scale-from "$dsi_res"
            --same-as "$selected_dsi"
        )
    
    "${xrandr_cmd[@]}"

    radxa-map-tp
}

__hardware() {
    menu_init
    menu_add __hardware_video "Video capture devices"
    menu_add __hardware_gpio_leds "GPIO LEDs"
    menu_add __hardware_thermal "Thermal governor"
    menu_add __hardware_dsi_mirror "Enable DSI mirroring display"
    if $DEBUG
    then
        menu_add __hardware_rgb_leds "RGB LEDs"
    fi
    menu_show "Manage on-board hardware"
}