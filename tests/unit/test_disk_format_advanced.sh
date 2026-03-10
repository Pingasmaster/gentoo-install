#!/bin/bash
# Tests for advanced filesystem formatting functions in EXECUTION mode
# format_zfs_standard, format_bcachefs_standard, disk_format_zfs, disk_format_btrfs, disk_format_bcachefs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

unset disk_action_summarize_only
setup_device_resolution

########################################
# format_zfs_standard
########################################

test_begin "format_zfs_standard: basic pool creation"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=([ashift]=12)
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "/dev/sda (test)" pool_props dataset_props "/dev/sda"
assert_eq 0 "$rc"
assert_contains "STUB:zpool create" "$out"
assert_contains "rpool" "$out"
assert_contains "/dev/sda" "$out"

test_begin "format_zfs_standard: includes default dataset props"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_contains "mountpoint=none" "$out"
assert_contains "canmount=noauto" "$out"
assert_contains "devices=off" "$out"

test_begin "format_zfs_standard: pool properties passed as -o"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=([ashift]=12 [autotrim]=on)
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_contains "-o" "$out"

test_begin "format_zfs_standard: encryption enabled adds encryption args"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "true" "false" "desc" pool_props dataset_props "/dev/sda"
assert_contains "encryption=aes-256-gcm" "$out"
assert_contains "keyformat=passphrase" "$out"
assert_contains "keylocation=prompt" "$out"

test_begin "format_zfs_standard: encryption disabled has no encryption args"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_not_contains "encryption=aes-256-gcm" "$out"

test_begin "format_zfs_standard: compression enabled calls zfs set"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "zstd" "desc" pool_props dataset_props "/dev/sda"
assert_contains "STUB:zfs set compression=zstd rpool" "$out"

test_begin "format_zfs_standard: compression disabled skips zfs set"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_not_contains "STUB:zfs set compression=" "$out"

test_begin "format_zfs_standard: creates ROOT and default datasets"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_contains "STUB:zfs create rpool/ROOT" "$out"
assert_contains "STUB:zfs create -o mountpoint=/ rpool/ROOT/default" "$out"
assert_contains "STUB:zpool set bootfs=rpool/ROOT/default rpool" "$out"

test_begin "format_zfs_standard: zpool create failure dies"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
function zpool() { return 1; }
declare -A pool_props=()
declare -A dataset_props=()
capture_output out rc format_zfs_standard "false" "false" "desc" pool_props dataset_props "/dev/sda"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function zpool() { echo "STUB:zpool $*"; }

########################################
# format_bcachefs_standard
########################################

test_begin "format_bcachefs_standard: unencrypted format and mount"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
_bcs_extra=()
_bcs_devs=("/dev/sda")
capture_output out rc format_bcachefs_standard "false" "desc" _bcs_extra _bcs_devs
assert_eq 0 "$rc"
assert_contains "STUB:bcachefs format" "$out"
assert_contains "STUB:mount -t bcachefs" "$out"

test_begin "format_bcachefs_standard: encrypted format pipes key"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
_bcs_extra=("--encrypted")
_bcs_devs=("/dev/sda")
capture_output out rc format_bcachefs_standard "true" "desc" _bcs_extra _bcs_devs
assert_eq 0 "$rc"
assert_contains "STUB:bcachefs format" "$out"
assert_contains "STUB:bcachefs mount" "$out"

test_begin "format_bcachefs_standard: unencrypted uses mount -t bcachefs"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
_bcs_extra=()
_bcs_devs=("/dev/sda")
capture_output out rc format_bcachefs_standard "false" "desc" _bcs_extra _bcs_devs
assert_contains "STUB:mount -t bcachefs" "$out"

test_begin "format_bcachefs_standard: multi-device mount string"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
_bcs_extra=()
_bcs_devs=("/dev/sda" "/dev/sdb" "/dev/sdc")
capture_output out rc format_bcachefs_standard "false" "desc" _bcs_extra _bcs_devs
assert_eq 0 "$rc"
assert_contains "STUB:mount -t bcachefs /dev/sda:/dev/sdb:/dev/sdc" "$out"

test_begin "format_bcachefs_standard: format failure dies"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
function bcachefs() { echo "bcachefs failed" >&2; return 1; }
_bcs_extra=()
_bcs_devs=("/dev/sda")
capture_output out rc format_bcachefs_standard "false" "desc" _bcs_extra _bcs_devs
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function bcachefs() { echo "STUB:bcachefs $*"; }

########################################
# disk_format_zfs
########################################

test_begin "disk_format_zfs exec: standard pool with defaults"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="zp" id="gpt" size="remaining" type="linux"
format_zfs ids="zp" pool_type="standard"
capture_output out rc apply_disk_action "action=format_zfs" "ids=zp" "pool_type=standard" "encrypt=false" "compress=false"
assert_eq 0 "$rc"
assert_contains "STUB:wipefs" "$out"
assert_contains "STUB:zpool create" "$out"

test_begin "disk_format_zfs exec: multiple devices resolved"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="z1" id="g1" size="remaining" type="linux"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="z2" id="g2" size="remaining" type="linux"
format_zfs ids="z1;z2" pool_type="standard"
capture_output out rc apply_disk_action "action=format_zfs" "ids=z1;z2" "pool_type=standard" "encrypt=false" "compress=false"
assert_eq 0 "$rc"
assert_contains "$_FAKE_DEV_DIR/z1" "$out"
assert_contains "$_FAKE_DEV_DIR/z2" "$out"

test_begin "disk_format_zfs exec: encrypt=true passes encryption"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="zp" id="gpt" size="remaining" type="linux"
format_zfs ids="zp" pool_type="standard" encrypt=true
capture_output out rc apply_disk_action "action=format_zfs" "ids=zp" "pool_type=standard" "encrypt=true" "compress=false"
assert_contains "encryption=aes-256-gcm" "$out"

test_begin "disk_format_zfs exec: non-default ashift"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="zp" id="gpt" size="remaining" type="linux"
format_zfs ids="zp" pool_type="standard"
capture_output out rc apply_disk_action "action=format_zfs" "ids=zp" "pool_type=standard" "encrypt=false" "compress=false" "ashift=13"
assert_contains "ashift=13" "$out"

test_begin "disk_format_zfs exec: non-default autotrim"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="zp" id="gpt" size="remaining" type="linux"
format_zfs ids="zp" pool_type="standard"
capture_output out rc apply_disk_action "action=format_zfs" "ids=zp" "pool_type=standard" "encrypt=false" "compress=false" "autotrim=on"
assert_contains "autotrim=on" "$out"

test_begin "disk_format_zfs exec: compression passes through"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="zp" id="gpt" size="remaining" type="linux"
format_zfs ids="zp" pool_type="standard" compress=lz4
capture_output out rc apply_disk_action "action=format_zfs" "ids=zp" "pool_type=standard" "encrypt=false" "compress=lz4"
assert_contains "STUB:zfs set compression=lz4 rpool" "$out"

########################################
# disk_format_btrfs
########################################

test_begin "disk_format_btrfs exec: basic single device"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type="
assert_eq 0 "$rc"
assert_contains "STUB:wipefs" "$out"
assert_contains "STUB:mkfs.btrfs -q" "$out"

test_begin "disk_format_btrfs exec: with raid_type"
reset_disk_state
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="b1" id="g1" size="remaining" type="linux"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="b2" id="g2" size="remaining" type="linux"
format_btrfs ids="b1;b2" raid_type="raid1"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=b1;b2" "label=" "raid_type=raid1"
assert_contains "-d raid1" "$out"

test_begin "disk_format_btrfs exec: with label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp" label="myfs"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=myfs" "raid_type="
assert_contains "-L myfs" "$out"

test_begin "disk_format_btrfs exec: non-default checksum"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type=" "checksum=xxhash"
assert_contains "--csum xxhash" "$out"

test_begin "disk_format_btrfs exec: default checksum is omitted"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type="
assert_not_contains "--csum" "$out"

test_begin "disk_format_btrfs exec: non-default nodesize"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type=" "nodesize=32k"
assert_contains "-n 32k" "$out"

test_begin "disk_format_btrfs exec: non-default sectorsize"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type=" "sectorsize=4096"
assert_contains "-s 4096" "$out"

test_begin "disk_format_btrfs exec: mixed=true adds -M flag"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type=" "mixed=true"
assert_contains "-M" "$out"

test_begin "disk_format_btrfs exec: non-auto metadata_raid"
reset_disk_state
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="b1" id="g1" size="remaining" type="linux"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="b2" id="g2" size="remaining" type="linux"
format_btrfs ids="b1;b2"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=b1;b2" "label=" "raid_type=" "metadata_raid=raid1"
assert_contains "-m raid1" "$out"

test_begin "disk_format_btrfs exec: init_btrfs called on first device"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bp" id="gpt" size="remaining" type="linux"
format_btrfs ids="bp"
capture_output out rc apply_disk_action "action=format_btrfs" "ids=bp" "label=" "raid_type="
assert_eq 0 "$rc"
# init_btrfs should be called (mounts, creates subvolume, etc.)
assert_contains "STUB:btrfs subvolume create" "$out"

########################################
# disk_format_bcachefs
########################################

test_begin "disk_format_bcachefs exec: basic unencrypted"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false"
assert_eq 0 "$rc"
assert_contains "STUB:wipefs" "$out"
assert_contains "STUB:bcachefs format" "$out"

test_begin "disk_format_bcachefs exec: encrypted adds --encrypted flag"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc" encrypt=true
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=true" "compress=false"
assert_contains "--encrypted" "$out"

test_begin "disk_format_bcachefs exec: compression adds flag"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc" compress=zstd
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=zstd"
assert_contains "--compression=zstd" "$out"

test_begin "disk_format_bcachefs exec: non-default data_checksum"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "data_checksum=xxhash"
assert_contains "--data_checksum=xxhash" "$out"

test_begin "disk_format_bcachefs exec: default data_checksum omitted"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false"
assert_not_contains "--data_checksum" "$out"

test_begin "disk_format_bcachefs exec: boolean option discard=true"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "discard=true"
assert_contains "--discard" "$out"

test_begin "disk_format_bcachefs exec: inline_data=false adds flag"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "inline_data=false"
assert_contains "--inline_data=false" "$out"

test_begin "disk_format_bcachefs exec: inline_data=true (default) omitted"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false"
assert_not_contains "--inline_data" "$out"

test_begin "disk_format_bcachefs exec: target options"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "foreground_target=ssd"
assert_contains "--foreground_target=ssd" "$out"

test_begin "disk_format_bcachefs exec: multi-device"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="bc1" id="g1" size="remaining" type="linux"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="bc2" id="g2" size="remaining" type="linux"
format_bcachefs ids="bc1;bc2"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc1;bc2" "encrypt=false" "compress=false"
assert_eq 0 "$rc"
assert_contains "$_FAKE_DEV_DIR/bc1" "$out"
assert_contains "$_FAKE_DEV_DIR/bc2" "$out"

test_begin "disk_format_bcachefs exec: erasure_code boolean"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "erasure_code=true"
assert_contains "--erasure_code" "$out"

test_begin "disk_format_bcachefs exec: non-default bg_compress"
reset_disk_state
ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="bc" id="gpt" size="remaining" type="linux"
format_bcachefs ids="bc"
capture_output out rc apply_disk_action "action=format_bcachefs" "ids=bc" "encrypt=false" "compress=false" "bg_compress=lz4"
assert_contains "--background_compression=lz4" "$out"

test_summary
