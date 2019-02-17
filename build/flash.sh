#!/usr/bin/env bash

set -e

ROOT=$(dirname "${BASH_SOURCE[0]}")/..
source "${ROOT}/build/common.sh"

function home-k8s::flash-device() {
    local image="$1"
    local target_device="$2"
    home-k8s::log "dd if=$image of=$target_device bs=100m"
    sudo dd if="${image}" of="${target_device}" bs=100m
}

function home-k8s::flash-device-safe() {
    local image="$1"
    local target_device="$2"

    home-k8s::log "About to flash device $target_device"
    home-k8s::log "Do you wish overwrite the device? (dangerious)"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) home-k8s::flash-device "$image" "$target_device"; break;;
            No ) exit;;
        esac
    done
}
