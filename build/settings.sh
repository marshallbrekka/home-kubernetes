#!/usr/bin/env bash

set -e

ROOT=$(dirname "${BASH_SOURCE[0]}")/..
source "${ROOT}/build/common.sh"


# Note: Tutorial on how to use the associative arrays
#
# Since we do a lot of variable lookup by strings, there is a very
# specific way that the maps must be accessed.
# Given a variable that contains a string, which presents the name of one of our
# associative arrays:
#
#   var_name="home_k8s_machine_settings_master1"
#
# We have to first save our desired field access to ANOTHER variable (if you find a way to
# do this without the middle step, please tell me).
#
#   field_ref=$var_name[board]
#
# After we have `field_ref`, we can use parameter expansion to get the desired field value.
#
#   board_name="${!field_ref}"
#
# Put all togeth, to get the `board` field from the
# map named `home_k8s_machine_settings_master1`.
#
#   var_name="home_k8s_machine_settings_master1"
#   field_ref=$var_name[board]
#   board_name="${!field_ref}"


##
## Base OS Images by board type
##

declare -A home_k8s_machine_board_os_renegade=(
    [base_url]="https://dl.armbian.com/renegade/archive/"
    [version_name]="Armbian_5.70_Renegade_Debian_stretch_default_4.4.167"
)
declare -A home_k8s_machine_board_os_bananapi=(
    [base_url]="https://dl.armbian.com/bananapi/archive/"
    [version_name]="Armbian_5.69_Bananapi_Debian_stretch_next_4.19.13"
)

declare -A home_k8s_machine_board_os=(
    [renegade]=home_k8s_machine_board_os_renegade
    [bananapi]=home_k8s_machine_board_os_bananapi
)


##
## Machine settings by identity
##

declare -A home_k8s_machine_settings_master1=(
    [hostname]=master-1
    [ip]=192.168.3.10
    [board]=renegade
)
declare -A home_k8s_machine_settings_master2=(
    [hostname]=master-2
    [ip]=192.168.1.11
    [board]=renegade
)
declare -A home_k8s_machine_settings_master3=(
    [hostname]=master-3
    [ip]=192.168.1.12
    [board]=bananapi
)

declare -A home_k8s_machine_settings=(
    [master-1]=home_k8s_machine_settings_master1
    [master-2]=home_k8s_machine_settings_master2
    [master-3]=home_k8s_machine_settings_master3
)

# Downloads the base os (.img file) and returns its file name
# Args:
#  $1 - base_image directory
#  $2 - base_url
#  $3 - version
function home-k8s::download-os() {
    local image_dir="$1"
    local base_url="$2"
    local version="$3"

    mkdir -p "$image_dir"

    if [ ! -f "${image_dir}/${version}.7z" ]; then
        home-k8s::log-attrs "Downloading base os" \
                            "Image Dir" "$image_dir" \
                            "Base url" "$base_url" \
                            "Version" "$version"
        $(curl -o "${image_dir}/${version}.7z" "${base_url}/${version}.7z")
    fi

    if [ ! -f "${image_dir}/${version}.img" ]; then
        home-k8s::log "Extracting ${version}.7z"
        $(7z e -o"${image_dir}" "${image_dir}/${version}.7z" "${version}.img")
    else
        home-k8s::log-attrs "Base os already exists" \
                            "Image Dir" "$image_dir" \
                            "Version" "$version"
    fi

    echo "${image_dir}/${version}.img"
}

# Writes the network interface and hostname configs
# into the machine build directory.
# Args:
#  $1 - machine_dir: the root fs directory for overlaying for the desired machine
#  $2 - machine_ip: the desired ip address of the machine
#  $3 - machine_host: the desired hostname of the machine
function home-k8s::builder::network() {
    local machine_dir="$1"
    local machine_ip="$2"
    local machine_hostname="$3"

    home-k8s::log-attrs "Writing network configuration to ${machine_dir}" \
                        "IP Address" "$machine_ip" \
                        "Hostname" "$machine_hostname"

    mkdir -p "${machine_dir}/etc/network/interfaces.d"
    echo "$machine_hostname" > "${machine_dir}/etc/hostname"

    cat >"${machine_dir}/etc/network/interfaces.d/eth0" <<EOL
auto eth0
allow-hotplug eth0
iface eth0 inet static
address ${machine_ip}
EOL
}


# Builds a final machine disk image.
# Args:
#  $1 - build_dir: The main build directory to save artifacts to.
#  $2 - machine_identity: The machine to build (ex: master-1).
#                         This will be one of the entires in home_k8s_machine_settings.
function home-k8s::builder::image() {
    local build_dir="$1"
    local machine_identity="$2"

    local image_dir="${build_dir}/base_image"
    local machine_dir="${build_dir}/machines/${machine_identity}"
    local machine_overlay="${machine_dir}/overlay/"

    local machine_settings=${home_k8s_machine_settings[$machine_identity]}
    local board_name=$machine_settings[board]

    local os_details=${home_k8s_machine_board_os[${!board_name}]}
    local os_base_url=$os_details[base_url]
    local os_version_name=$os_details[version_name]

    home-k8s::log-attrs "Building image for ${machine_identity}" \
                        "Board" "${!board_name}" \
                        "OS Version" "${!os_version_name}"
    image_location=$(home-k8s::download-os "$image_dir" "${!os_base_url}" "${!os_version_name}")

    local machine_ip=$machine_settings[ip]
    local machine_hostname=$machine_settings[hostname]
    home-k8s::builder::network "$machine_overlay" "${!machine_ip}" "${!machine_hostname}"

    # Write the overlay contents to the image
    home-k8s::builder::overlay "$machine_dir" "$image_location"

    # Mv the final image to the artifacts dir
    local final_image_name="${build_dir}/images/${machine_identity}-$(date +%s).img"
    home-k8s::log "Moving final image to ${final_image_name}"
    mkdir -p "${build_dir}/images"
    mv "${machine_dir}/image.img" "${final_image_name}"
}

function home-k8s::builder::overlay() {
    local machine_dir="$1"
    local source_image="$2"

    home-k8s::log-attrs "Calculating offset of disk image" \
                        "Disk Image" "${source_image}"
    local sector_size=512
    local sector_start=$(sfdisk --json "$source_image" | jq '.partitiontable.partitions[0].start')
    local offset_size=$(($sector_size * $sector_start))

    # Move the source image into the destination
    cp "$source_image" "${machine_dir}/image.img"

    # Make a mount point
    mkdir -p "${machine_dir}/mount"

    # Mount the .img file
    home-k8s::log-attrs "Mounting disk ${machine_dir}/image.img" \
                        "Sector Size" $sector_size \
                        "Sector Start" $sector_start \
                        "Offset" $offset_size \
                        "Mount" "${machine_dir}/mount"
    home-k8s::log "mount -o offset=${offset_size} ${machine_dir}/image.img ${machine_dir}/mount"
    mount -o offset=${offset_size} ${machine_dir}/image.img ${machine_dir}/mount

    # Copy the overlay changes
    home-k8s::log-attrs "Copying overlay onto disk" \
                        "Overlay Dir" "'${machine_dir}/overlay/*'" \
                        "Disk Dir" "'${machine_dir}/mount/'"
    home-k8s::log "cp --recursive ${machine_dir}/overlay/* ${machine_dir}/mount/"
    cp --recursive ${machine_dir}/overlay/* ${machine_dir}/mount/

    # And safely unmount
    umount ${machine_dir}/mount
}

# Example building of an image.
# home-k8s::builder::image artifacts master-1
