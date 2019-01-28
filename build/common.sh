#!/usr/bin/env bash

function home-k8s::log() {
   (>&2 echo "$@")
}

# Logs a message and pairs of attributes
# Ex: log-attrs "Message here" attr1 value1 attr2 value2
# Outputs:
# Message here
#   attr1: value1
#   attr2: value2
function home-k8s::log-attrs() {
    (>&2 echo "${1}")

    for (( i=2; i<=$#; i=i+2)); do
        j=$((i+1))
        (>&2 echo -e "  ${!i}:\t${!j}")
    done
    (>&2 echo "")
}

