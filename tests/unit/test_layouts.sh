#!/bin/bash
# Tests for high-level disk layout functions: ZFS, RAID, btrfs, bcachefs layouts
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# create_zfs_centric_layout
########################################

test_begin "create_zfs_centric_layout: single disk efi"
reset_disk_state
create_zfs_centric_layout swap=8GiB /dev/sda
assert_eq true "$USED_ZFS"
assert_eq "part_efi_dev0" "$DISK_ID_EFI"
assert_eq "part_swap_dev0" "$DISK_ID_SWAP"
assert_eq "zfs" "$DISK_ID_ROOT_TYPE"
assert_contains "action=format_zfs" "${DISK_ACTIONS[*]}"

test_begin "create_zfs_centric_layout: no swap"
reset_disk_state
create_zfs_centric_layout swap=false /dev/sda
assert_eq true "$USED_ZFS"
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)" "no swap expected"

test_begin "create_zfs_centric_layout: bios type"
reset_disk_state
create_zfs_centric_layout swap=4GiB type=bios /dev/sda
assert_eq "part_bios_dev0" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)"

test_begin "create_zfs_centric_layout: with encryption"
reset_disk_state
create_zfs_centric_layout swap=false encrypt=true /dev/sda
assert_eq true "$USED_ENCRYPTION"

test_begin "create_zfs_centric_layout: with compression"
reset_disk_state
_tmp_err="$(mktemp)"
create_zfs_centric_layout swap=false compress=zstd /dev/sda 2>"$_tmp_err"; rc=$?
out="$(cat "$_tmp_err")"; rm -f "$_tmp_err"
assert_eq 0 "$rc"
assert_contains "action=format_zfs" "${DISK_ACTIONS[*]}"

test_begin "create_zfs_centric_layout: multi-disk"
reset_disk_state
create_zfs_centric_layout swap=4GiB /dev/sda /dev/sdb
assert_eq true "$USED_ZFS"
# First disk gets gpt_dev0, additional disks get root_dev$i via create_dummy
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[root_dev1] ]] && echo true || echo false)"

test_begin "create_zfs_centric_layout: with all ZFS options"
reset_disk_state
out="$(create_zfs_centric_layout swap=false \
	ashift=12 autotrim=on recordsize=128K checksum=sha256 \
	acltype=posix atime=off xattr=sa dnodesize=auto \
	/dev/sda 2>&1)"; rc=$?
assert_eq 0 "$rc"

########################################
# create_raid0_luks_layout
########################################

test_begin "create_raid0_luks_layout: basic 2-disk"
reset_disk_state
create_raid0_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
assert_eq true "$USED_RAID"
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_contains "action=create_raid" "${DISK_ACTIONS[*]}"
assert_contains "action=create_luks" "${DISK_ACTIONS[*]}"
assert_eq "ext4" "$DISK_ID_ROOT_TYPE"

test_begin "create_raid0_luks_layout: no swap"
reset_disk_state
create_raid0_luks_layout swap=false root_fs=ext4 /dev/sda /dev/sdb
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

test_begin "create_raid0_luks_layout: btrfs root"
reset_disk_state
create_raid0_luks_layout swap=4GiB root_fs=btrfs /dev/sda /dev/sdb
assert_eq true "$USED_BTRFS"
assert_eq "btrfs" "$DISK_ID_ROOT_TYPE"

test_begin "create_raid0_luks_layout: bcachefs root"
reset_disk_state
create_raid0_luks_layout swap=4GiB root_fs=bcachefs /dev/sda /dev/sdb
assert_eq true "$USED_BCACHEFS"
assert_eq "bcachefs" "$DISK_ID_ROOT_TYPE"

########################################
# create_btrfs_centric_layout
########################################

test_begin "create_btrfs_centric_layout: single disk"
reset_disk_state
create_btrfs_centric_layout swap=4GiB /dev/sda
assert_eq true "$USED_BTRFS"
assert_eq "btrfs" "$DISK_ID_ROOT_TYPE"
assert_contains "action=format_btrfs" "${DISK_ACTIONS[*]}"

test_begin "create_btrfs_centric_layout: multi-disk"
reset_disk_state
create_btrfs_centric_layout swap=4GiB /dev/sda /dev/sdb
assert_eq true "$USED_BTRFS"
# First disk gets gpt_dev0, additional disks get root_dev$i via create_dummy
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[root_dev1] ]] && echo true || echo false)"

test_begin "create_btrfs_centric_layout: with luks"
reset_disk_state
create_btrfs_centric_layout swap=4GiB luks=true /dev/sda
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"

test_begin "create_btrfs_centric_layout: no swap"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

test_begin "create_btrfs_centric_layout: bios type"
reset_disk_state
create_btrfs_centric_layout swap=false type=bios /dev/sda
assert_eq "part_bios_dev0" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)"

test_begin "create_btrfs_centric_layout: with optional btrfs args"
reset_disk_state
out="$(create_btrfs_centric_layout swap=false checksum=xxhash nodesize=32k sectorsize=4096 /dev/sda 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "create_btrfs_centric_layout: mount opts include compress"
reset_disk_state
create_btrfs_centric_layout swap=false /dev/sda
assert_contains "compress" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "subvol=/root" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# create_bcachefs_centric_layout
########################################

test_begin "create_bcachefs_centric_layout: single disk"
reset_disk_state
create_bcachefs_centric_layout swap=4GiB /dev/sda
assert_eq true "$USED_BCACHEFS"
assert_eq "bcachefs" "$DISK_ID_ROOT_TYPE"
assert_contains "action=format_bcachefs" "${DISK_ACTIONS[*]}"

test_begin "create_bcachefs_centric_layout: with encryption"
reset_disk_state
create_bcachefs_centric_layout swap=false encrypt=true /dev/sda
assert_eq true "$USED_ENCRYPTION"
assert_eq true "$USED_BCACHEFS"

test_begin "create_bcachefs_centric_layout: multi-disk"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda /dev/sdb
assert_eq true "$USED_BCACHEFS"
# Should have BCACHEFS_DEVICE_IDS set
assert_eq true "$([[ -v BCACHEFS_DEVICE_IDS ]] && echo true || echo false)"

test_begin "create_bcachefs_centric_layout: no swap"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

test_begin "create_bcachefs_centric_layout: with optional args"
reset_disk_state
out="$(create_bcachefs_centric_layout swap=false compress=zstd data_checksum=xxhash block_size=4k /dev/sda 2>&1)"; rc=$?
assert_eq 0 "$rc"

########################################
# create_existing_partitions_layout
########################################

test_begin "create_existing_partitions_layout: sets NO_PARTITIONING flag"
reset_disk_state
create_existing_partitions_layout swap=/dev/sda2 boot=/dev/sda1 /dev/sda3
assert_eq true "$NO_PARTITIONING_OR_FORMATTING"

test_begin "create_existing_partitions_layout: empty root type"
reset_disk_state
create_existing_partitions_layout swap=false boot=/dev/sda1 /dev/sda2
assert_eq "" "$DISK_ID_ROOT_TYPE"

########################################
# create_single_disk_layout (deprecated)
########################################

test_begin "create_single_disk_layout: shows deprecation message"
reset_disk_state
out="$(create_single_disk_layout 2>&1)"; rc=$?
assert_contains "deprecated" "$out"

########################################
# Edge cases
########################################

test_begin "edge case: layout with very long device path"
reset_disk_state
create_classic_single_disk_layout swap=4GiB /dev/disk/by-id/ata-VBOX_HARDDISK_VB12345678-90abcdef
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_begin "edge case: layout with nvme device"
reset_disk_state
create_classic_single_disk_layout swap=8GiB /dev/nvme0n1
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_summary
