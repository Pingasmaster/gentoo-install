#!/bin/bash
# Tests for disk_* action functions (summary mode) and apply_disk_action dispatch
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

# All tests run in summarize mode to avoid touching real disks
disk_action_summarize_only=true

########################################
# apply_disk_action: dispatch
########################################

test_begin "apply_disk_action: dispatches existing action"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
register_existing new_id="dev" device="/dev/sda1"
apply_disk_action "action=existing" "new_id=dev" "device=/dev/sda1"
assert_eq "/dev/sda1" "${summary_name[dev]}"
assert_contains "no-format" "${summary_hint[dev]}"

test_begin "apply_disk_action: dispatches create_gpt with device"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
apply_disk_action "action=create_gpt" "new_id=gpt" "device=/dev/sda"
assert_eq "/dev/sda" "${summary_name[gpt]}"
assert_contains "(gpt)" "${summary_hint[gpt]}"

test_begin "apply_disk_action: dispatches create_gpt with id"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
register_existing new_id="base" device="/dev/sda"
create_gpt new_id="gpt" id="base"
apply_disk_action "action=create_gpt" "new_id=gpt" "id=base"
assert_eq "gpt" "${summary_name[gpt]}"
# When using id, the entry is a child of that id
assert_contains "gpt" "${summary_tree[base]}"

test_begin "apply_disk_action: dispatches create_partition"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="1GiB" type="efi"
apply_disk_action "action=create_partition" "new_id=p1" "id=gpt" "size=1GiB" "type=efi"
assert_eq "part" "${summary_name[p1]}"
assert_contains "(efi)" "${summary_hint[p1]}"
assert_contains "p1" "${summary_tree[gpt]}"

test_begin "apply_disk_action: dispatches create_dummy"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_dummy new_id="dum" device="/dev/sdb"
apply_disk_action "action=create_dummy" "new_id=dum" "device=/dev/sdb"
assert_eq "/dev/sdb" "${summary_name[dum]}"

test_begin "apply_disk_action: dispatches create_luks with id"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
create_luks new_id="crypt" name="root" id="p1"
apply_disk_action "action=create_luks" "new_id=crypt" "name=root" "id=p1"
assert_eq "luks" "${summary_name[crypt]}"
assert_contains "crypt" "${summary_tree[p1]}"

test_begin "apply_disk_action: dispatches create_luks with device"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_luks new_id="crypt2" name="crypt" device="/dev/sdb"
apply_disk_action "action=create_luks" "new_id=crypt2" "name=crypt" "device=/dev/sdb"
assert_eq "/dev/sdb" "${summary_name[crypt2]}"
assert_contains "(luks)" "${summary_hint[crypt2]}"

########################################
# disk_format: summary mode, all types
########################################

test_begin "disk_format summary: ext4"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="ext4" label="root"
apply_disk_action "action=format" "id=p1" "type=ext4" "label=root"
assert_eq "ext4" "${summary_name[__fs__p1]}"
assert_contains "(fs)" "${summary_hint[__fs__p1]}"

test_begin "disk_format summary: efi"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="1GiB" type="efi"
format id="p1" type="efi" label="efi"
apply_disk_action "action=format" "id=p1" "type=efi" "label=efi"
assert_eq "efi" "${summary_name[__fs__p1]}"

test_begin "disk_format summary: swap"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="8GiB" type="swap"
format id="p1" type="swap" label="swap"
apply_disk_action "action=format" "id=p1" "type=swap" "label=swap"
assert_eq "swap" "${summary_name[__fs__p1]}"

test_begin "disk_format summary: btrfs"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="btrfs" label="root"
apply_disk_action "action=format" "id=p1" "type=btrfs" "label=root"
assert_eq "btrfs" "${summary_name[__fs__p1]}"

test_begin "disk_format summary: bios"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="1GiB" type="bios"
format id="p1" type="bios" label="bios"
apply_disk_action "action=format" "id=p1" "type=bios" "label=bios"
assert_eq "bios" "${summary_name[__fs__p1]}"

########################################
# disk_format_zfs: summary mode
########################################

test_begin "disk_format_zfs summary: creates fs entries for each id"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
create_dummy new_id="d2" device="/dev/sdb"
format_zfs ids="p1;d2"
apply_disk_action "action=format_zfs" "ids=p1;d2" "pool_type=standard" "encrypt=false" "compress=false"
assert_eq "zfs" "${summary_name[__fs__p1]}"
assert_eq "zfs" "${summary_name[__fs__d2]}"

########################################
# disk_format_btrfs: summary mode
########################################

test_begin "disk_format_btrfs summary: creates fs entries for each id"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
create_dummy new_id="d2" device="/dev/sdb"
format_btrfs ids="p1;d2"
apply_disk_action "action=format_btrfs" "ids=p1;d2" "label=root" "raid_type=raid0"
assert_eq "btrfs" "${summary_name[__fs__p1]}"
assert_eq "btrfs" "${summary_name[__fs__d2]}"

########################################
# disk_format_bcachefs: summary mode
########################################

test_begin "disk_format_bcachefs summary: creates fs entries for each id"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
create_dummy new_id="d2" device="/dev/sdb"
format_bcachefs ids="p1;d2"
apply_disk_action "action=format_bcachefs" "ids=p1;d2" "encrypt=false" "compress=false"
assert_eq "bcachefs" "${summary_name[__fs__p1]}"
assert_eq "bcachefs" "${summary_name[__fs__d2]}"

########################################
# disk_create_raid: summary mode
########################################

test_begin "disk_create_raid summary: creates entries for members and root"
reset_disk_state
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="__unused__"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
create_gpt new_id="gpt1" device="/dev/sda"
create_partition new_id="p1" id="gpt1" size="10GiB" type="raid"
create_gpt new_id="gpt2" device="/dev/sdb"
create_partition new_id="p2" id="gpt2" size="10GiB" type="raid"
create_raid new_id="md" level=1 name="root" ids="p1;p2"
apply_disk_action "action=create_raid" "new_id=md" "level=1" "name=root" "ids=p1;p2"
# Root entry for the assembled array
assert_match "raid1" "${summary_name[md]}"
# Member entries (prefixed with _)
assert_match "raid1" "${summary_name[_md]}"

########################################
# apply_disk_action: invalid action
########################################

test_begin "apply_disk_action: unknown action prints warning"
reset_disk_state
out="$(apply_disk_action "action=bogus_action" 2>&1)"
assert_contains "Ignoring invalid action" "$out"

########################################
# Full summary pipeline integration
########################################

test_begin "full summary: classic efi+swap+ext4 layout generates correct tree"
reset_disk_state
create_classic_single_disk_layout swap=8GiB root_fs=ext4 /dev/sda
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
# Should have device at root
assert_contains "gpt" "${summary_tree[__root__]}"
# GPT should have partitions as children
assert_contains "part_efi" "${summary_tree[gpt]}"
assert_contains "part_swap" "${summary_tree[gpt]}"
assert_contains "part_root" "${summary_tree[gpt]}"

test_begin "full summary: classic bios+luks layout generates correct tree"
reset_disk_state
create_classic_single_disk_layout swap=4GiB type=bios luks=true /dev/sda
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
assert_contains "gpt" "${summary_tree[__root__]}"
# LUKS should be child of part_root
assert_contains "part_luks_root" "${summary_tree[part_root]}"

test_begin "full summary: zfs layout generates correct tree"
reset_disk_state
create_zfs_centric_layout swap=4GiB /dev/sda /dev/sdb
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
assert_contains "gpt_dev0" "${summary_tree[__root__]}"
# Additional device should be at root level
assert_contains "root_dev1" "${summary_tree[__root__]}"

test_summary
