#!/bin/bash
# Tests for create_raid1_luks_layout (previously untested)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# create_raid1_luks_layout: basic
########################################

test_begin "create_raid1_luks_layout: basic 2-disk efi ext4"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
assert_eq true "$USED_RAID"
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_eq "ext4" "$DISK_ID_ROOT_TYPE"
assert_eq "part_luks_root" "$DISK_ID_ROOT"
assert_contains "defaults,noatime,errors=remount-ro,discard" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "create_raid1_luks_layout: uses raid level 1 (not 0)"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
# The DISK_ACTIONS should contain level=1
assert_contains "level=1" "${DISK_ACTIONS[*]}"
# Should NOT contain level=0
assert_not_contains "level=0" "${DISK_ACTIONS[*]}"

########################################
# create_raid1_luks_layout: all root fs types
########################################

test_begin "create_raid1_luks_layout: btrfs root"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=btrfs /dev/sda /dev/sdb
assert_eq true "$USED_BTRFS"
assert_eq "btrfs" "$DISK_ID_ROOT_TYPE"
assert_contains "compress=zstd" "$DISK_ID_ROOT_MOUNT_OPTS"
assert_contains "subvol=/root" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "create_raid1_luks_layout: bcachefs root"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=bcachefs /dev/sda /dev/sdb
assert_eq true "$USED_BCACHEFS"
assert_eq "bcachefs" "$DISK_ID_ROOT_TYPE"
assert_eq "defaults,noatime" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# create_raid1_luks_layout: no swap
########################################

test_begin "create_raid1_luks_layout: no swap"
reset_disk_state
create_raid1_luks_layout swap=false root_fs=ext4 /dev/sda /dev/sdb
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)" "no swap expected"
# Should not have raid for swap
assert_not_contains "part_raid_swap" "${DISK_ACTIONS[*]}"

test_begin "create_raid1_luks_layout: with swap sets DISK_ID_SWAP"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
assert_eq "part_raid_swap" "$DISK_ID_SWAP"

########################################
# create_raid1_luks_layout: boot type
########################################

test_begin "create_raid1_luks_layout: efi boot (default)"
reset_disk_state
create_raid1_luks_layout swap=false root_fs=ext4 /dev/sda /dev/sdb
# EFI is on the raid1 array of efi partitions
assert_eq "part_raid_efi" "$DISK_ID_EFI"
assert_eq false "$([[ -v DISK_ID_BIOS ]] && echo true || echo false)"

test_begin "create_raid1_luks_layout: bios boot"
reset_disk_state
create_raid1_luks_layout swap=false type=bios root_fs=ext4 /dev/sda /dev/sdb
assert_eq "part_raid_bios" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)"

########################################
# create_raid1_luks_layout: no luks
########################################

test_begin "create_raid1_luks_layout: luks=false skips encryption"
reset_disk_state
create_raid1_luks_layout swap=false luks=false root_fs=ext4 /dev/sda /dev/sdb
assert_eq true "$USED_RAID"
assert_eq false "$USED_LUKS"
assert_eq false "$USED_ENCRYPTION"
assert_eq "part_raid_root" "$DISK_ID_ROOT"

########################################
# create_raid1_luks_layout: 3 disks
########################################

test_begin "create_raid1_luks_layout: 3 disks"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb /dev/sdc
assert_eq true "$USED_RAID"
# Should have 3 GPTs
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt_dev1] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt_dev2] ]] && echo true || echo false)"
# Should have 3 root partitions in the raid
assert_eq true "$([[ -v DISK_ID_TO_UUID[part_root_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[part_root_dev1] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[part_root_dev2] ]] && echo true || echo false)"

########################################
# create_raid1_luks_layout: DISK_ACTIONS count
########################################

test_begin "create_raid1_luks_layout: action count with 2 disks, swap, luks"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
# 2 * (create_gpt + part_efi + part_swap + part_root) = 8
# + raid_efi + raid_swap + raid_root = 3
# + luks_root = 1
# + format_efi + format_swap + format_root = 3
# Total = 15
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 15 "$action_count" "2disk+swap+luks = 15 actions"

test_begin "create_raid1_luks_layout: action count with 2 disks, no swap, no luks"
reset_disk_state
create_raid1_luks_layout swap=false luks=false root_fs=ext4 /dev/sda /dev/sdb
# 2 * (create_gpt + part_efi + part_root) = 6
# + raid_efi + raid_root = 2
# + format_efi + format_root = 2
# Total = 10
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 10 "$action_count" "2disk no-swap no-luks = 10 actions"

########################################
# create_raid1_luks_layout: dracut cmdline
########################################

test_begin "create_raid1_luks_layout: dracut cmdline includes raid and luks"
reset_disk_state
create_raid1_luks_layout swap=4GiB root_fs=ext4 /dev/sda /dev/sdb
# Should have multiple rd.md.uuid entries (for efi, swap, root raids)
md_count=0
for entry in "${DISK_DRACUT_CMDLINE[@]}"; do
	[[ "$entry" == rd.md.uuid=* ]] && md_count=$((md_count + 1))
done
assert_eq 3 "$md_count" "should have 3 raid UUID cmdline entries (efi+swap+root)"
# Should also have luks UUID
assert_contains "rd.luks.uuid=" "${DISK_DRACUT_CMDLINE[*]}"

test_begin "create_raid1_luks_layout: no swap means 2 raid cmdline entries"
reset_disk_state
create_raid1_luks_layout swap=false root_fs=ext4 /dev/sda /dev/sdb
md_count=0
for entry in "${DISK_DRACUT_CMDLINE[@]}"; do
	[[ "$entry" == rd.md.uuid=* ]] && md_count=$((md_count + 1))
done
assert_eq 2 "$md_count" "should have 2 raid UUID cmdline entries (efi+root)"

########################################
# create_raid1_luks_layout: summary integration
########################################

test_begin "create_raid1_luks_layout: summary tree"
reset_disk_state
create_raid1_luks_layout swap=false luks=true root_fs=ext4 /dev/sda /dev/sdb
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "raid1" "$result"
assert_contains "luks" "$result"

test_summary
