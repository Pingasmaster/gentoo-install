#!/bin/bash
# Tests for btrfs mount option building in create_btrfs_centric_layout
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# Default mount options
########################################

test_begin "btrfs mount opts: defaults"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_contains "defaults" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "noatime" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "compress=zstd" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "space_cache=v2" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "subvol=/root" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# Compression options
########################################

test_begin "btrfs mount opts: compress=lzo"
reset_disk_state
create_btrfs_centric_layout swap=false compress=lzo /dev/sda
assert_contains "compress=lzo" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "compress=zstd" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: compress=none removes compress option"
reset_disk_state
create_btrfs_centric_layout swap=false compress=none /dev/sda
assert_not_contains "compress=" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: zstd with compress_level"
reset_disk_state
create_btrfs_centric_layout swap=false compress=zstd compress_level=3 /dev/sda
assert_contains "compress=zstd:3" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: non-zstd with compress_level ignores level"
reset_disk_state
create_btrfs_centric_layout swap=false compress=lzo compress_level=3 /dev/sda
assert_contains "compress=lzo" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "lzo:3" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# Discard options
########################################

test_begin "btrfs mount opts: discard=async"
reset_disk_state
create_btrfs_centric_layout swap=false discard=async /dev/sda
assert_contains "discard=async" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: discard=on"
reset_disk_state
create_btrfs_centric_layout swap=false discard=on /dev/sda
# discard=on is just "discard" without =async
assert_contains ",discard" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "discard=async" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: discard=off (default) - no discard"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_not_contains "discard" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# noatime option
########################################

test_begin "btrfs mount opts: noatime=true (default)"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_contains "noatime" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: noatime=false"
reset_disk_state
create_btrfs_centric_layout swap=false noatime=false /dev/sda
assert_not_contains "noatime" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# autodefrag option
########################################

test_begin "btrfs mount opts: autodefrag=off (default)"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_not_contains "autodefrag" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: autodefrag=on"
reset_disk_state
create_btrfs_centric_layout swap=false autodefrag=on /dev/sda
assert_contains "autodefrag" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# SSD option
########################################

test_begin "btrfs mount opts: ssd=auto (default) - no ssd flag"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_not_contains ",ssd" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "nossd" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: ssd=on"
reset_disk_state
create_btrfs_centric_layout swap=false ssd=on /dev/sda
assert_contains ",ssd" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "nossd" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: ssd=off"
reset_disk_state
create_btrfs_centric_layout swap=false ssd=off /dev/sda
assert_contains "nossd" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# space_cache option
########################################

test_begin "btrfs mount opts: space_cache=v2 (default)"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_contains "space_cache=v2" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: space_cache=v1"
reset_disk_state
create_btrfs_centric_layout swap=false space_cache=v1 /dev/sda
assert_contains "space_cache=v1" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "space_cache=v2" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# Combined options
########################################

test_begin "btrfs mount opts: all custom options combined"
reset_disk_state
create_btrfs_centric_layout swap=false \
	compress=zstd compress_level=9 \
	discard=async noatime=true \
	autodefrag=on space_cache=v2 ssd=on \
	/dev/sda
assert_contains "defaults" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "noatime" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "compress=zstd:9" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "discard=async" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "autodefrag" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "space_cache=v2" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains ",ssd" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "subvol=/root" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "btrfs mount opts: minimal options (no compression, no noatime)"
reset_disk_state
create_btrfs_centric_layout swap=false compress=none noatime=false /dev/sda
assert_contains "defaults" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "noatime" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_not_contains "compress" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "subvol=/root" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# Btrfs format options pass through
########################################

test_begin "btrfs format opts: checksum xxhash"
reset_disk_state
create_btrfs_centric_layout swap=false checksum=xxhash /dev/sda 2>/dev/null; rc=$?
assert_eq 0 "$rc"
assert_contains "action=format_btrfs" "${DISK_ACTIONS[*]}"

test_begin "btrfs format opts: custom nodesize"
reset_disk_state
create_btrfs_centric_layout swap=false nodesize=32k /dev/sda 2>/dev/null; rc=$?
assert_eq 0 "$rc"

test_begin "btrfs format opts: custom sectorsize"
reset_disk_state
create_btrfs_centric_layout swap=false sectorsize=4096 /dev/sda 2>/dev/null; rc=$?
assert_eq 0 "$rc"

test_begin "btrfs format opts: mixed mode"
reset_disk_state
create_btrfs_centric_layout swap=false mixed=true /dev/sda 2>/dev/null; rc=$?
assert_eq 0 "$rc"

########################################
# Multi-disk btrfs with LUKS
########################################

test_begin "btrfs multi-disk with luks: all disks get luks"
reset_disk_state
create_btrfs_centric_layout swap=false luks=true /dev/sda /dev/sdb /dev/sdc
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_eq true "$USED_BTRFS"
# Should have 3 LUKS volumes
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev1] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev2] ]] && echo true || echo false)"
# Root should be first luks device
assert_eq "luks_dev0" "$DISK_ID_ROOT"

test_begin "btrfs multi-disk without luks: uses dummies for additional disks"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda /dev/sdb
assert_eq false "$USED_LUKS"
assert_eq "part_root_dev0" "$DISK_ID_ROOT"
assert_eq true "$([[ -v DISK_ID_TO_UUID[root_dev1] ]] && echo true || echo false)"

test_summary
