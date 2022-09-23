# shellcheck shell=bash

source "$ROOT_PATH/usr/lib/rsetup/mod/dialog/basic.sh"
source "$ROOT_PATH/usr/lib/rsetup/mod/dialog/menu.sh"
source "$ROOT_PATH/usr/lib/rsetup/mod/dialog/checklist.sh"
source "$ROOT_PATH/usr/lib/rsetup/mod/dialog/radiolist.sh"
source "$ROOT_PATH/usr/lib/rsetup/mod/dialog/select.sh"

RSETUP_SCREEN=()

register_screen() {
    __parameter_count_check 1 "$@"
    if [[ "$1" != ":" ]]
    then
        __parameter_type_check "$1" "function"
    fi

    RSETUP_SCREEN+=( "$1" )
}

# shellcheck disable=SC2120
unregister_screen() {
    __parameter_count_check 0 "$@"

    RSETUP_SCREEN=( "${RSETUP_SCREEN[@]:0:$(( ${#RSETUP_SCREEN[@]} - 1 ))}" )
}

push_screen() {
    __parameter_count_check 1 "$@"

    register_screen "$1"
    register_screen ":"
}

tui_start() {
    __parameter_count_check 1 "$@"
    __parameter_type_check "$1" "function"

    register_screen "$1"
    while (( ${#RSETUP_SCREEN[@]} != 0 ))
    do
        ${RSETUP_SCREEN[-1]}
        unregister_screen
    done
}