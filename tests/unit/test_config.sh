#!/bin/bash
# Tests for scripts/config.sh: disk layout builders and config validation
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# create_new_id
########################################

test_begin "create_new_id: creates uuid entry"
reset_disk_state
declare -A arguments=([new_id]="test_id")
create_new_id new_id
assert_eq true "$([[ -v DISK_ID_TO_UUID[test_id] ]] && echo true || echo false)"

test_begin "create_new_id: rejects duplicate id"
reset_disk_state
declare -A arguments=([new_id]="dup_id")
create_new_id new_id
declare -A arguments=([new_id]="dup_id")
out="$(create_new_id new_id 2>&1)"; rc=$?
assert_contains "already exists" "$out"

test_begin "create_new_id: rejects semicolons in id"
reset_disk_state
declare -A arguments=([new_id]="bad;id")
out="$(create_new_id new_id 2>&1)"; rc=$?
assert_contains "invalid character" "$out"

########################################
# register_existing
########################################

test_begin "register_existing: registers device"
reset_disk_state
register_existing new_id="existing_dev" device="/dev/sda1"
assert_eq "device:/dev/sda1" "${DISK_ID_TO_RESOLVABLE[existing_dev]}"
assert_contains "action=existing" "${DISK_ACTIONS[*]}"

########################################
# create_gpt
########################################

test_begin "create_gpt: with device"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
assert_eq true "$([[ -v DISK_ID_TO_UUID[gpt] ]] && echo true || echo false)"
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"
assert_match "^ptuuid:" "${DISK_ID_TO_RESOLVABLE[gpt]}"

test_begin "create_gpt: with existing id"
reset_disk_state
register_existing new_id="base" device="/dev/sda"
create_gpt new_id="gpt" id="base"
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_begin "create_gpt: rejects both device and id"
reset_disk_state
register_existing new_id="base" device="/dev/sda"
out="$(create_gpt new_id="gpt" device="/dev/sda" id="base" 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

test_begin "create_gpt: rejects missing device and id"
reset_disk_state
out="$(create_gpt new_id="gpt" 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out"

########################################
# create_partition
########################################

test_begin "create_partition: basic efi partition"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
assert_eq true "$([[ -v DISK_ID_TO_UUID[part_efi] ]] && echo true || echo false)"
assert_eq "gpt" "${DISK_ID_PART_TO_GPT_ID[part_efi]}"
assert_contains "action=create_partition" "${DISK_ACTIONS[*]}"

test_begin "create_partition: size=remaining sets flag"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
assert_eq true "$([[ -v "DISK_GPT_HAD_SIZE_REMAINING[gpt]" ]] && echo true || echo false)"

test_begin "create_partition: rejects partition after size=remaining"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part1" id="gpt" size="remaining" type="linux"
out="$(create_partition new_id="part2" id="gpt" size="1GiB" type="efi" 2>&1)"; rc=$?
assert_contains "after size=remaining" "$out"

test_begin "create_partition: invalid type rejected"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
out="$(create_partition new_id="part1" id="gpt" size="1GiB" type="ntfs" 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

test_begin "create_partition: all valid types accepted"
for ptype in bios efi swap raid luks linux; do
	reset_disk_state
	create_gpt new_id="gpt" device="/dev/sda"
	out="$(create_partition new_id="p_$ptype" id="gpt" size="1GiB" type="$ptype" 2>&1)"; rc=$?
	if [[ $rc -ne 0 ]]; then
		test_fail "type=$ptype should be accepted"
		break
	fi
done
test_pass

test_begin "create_partition: nonexistent parent id rejected"
reset_disk_state
out="$(create_partition new_id="part1" id="nonexistent" size="1GiB" type="linux" 2>&1)"; rc=$?
assert_contains "not found" "$out"

########################################
# create_raid
########################################

test_begin "create_raid: basic raid1"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="10GiB" type="raid"
create_gpt new_id="gpt2" device="/dev/sdb"
create_partition new_id="p2" id="gpt2" size="10GiB" type="raid"
create_raid new_id="md_root" level=1 name="root" ids="p1;p2"
assert_eq true "$USED_RAID"
assert_contains "action=create_raid" "${DISK_ACTIONS[*]}"
assert_match "^mdadm:" "${DISK_ID_TO_RESOLVABLE[md_root]}"
# Should add dracut cmdline
assert_contains "rd.md.uuid=" "${DISK_DRACUT_CMDLINE[*]}"

test_begin "create_raid: invalid level rejected"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="10GiB" type="raid"
out="$(create_raid new_id="md" level=99 name="root" ids="p1" 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

test_begin "create_raid: valid levels accepted"
for level in 0 1 5 6; do
	reset_disk_state
	create_gpt new_id="gpt" device="/dev/sda"
	create_partition new_id="p1" id="gpt" size="10GiB" type="raid"
	out="$(create_raid new_id="md" level="$level" name="root" ids="p1" 2>&1)"; rc=$?
	if [[ $rc -ne 0 ]]; then
		test_fail "level=$level should be accepted"
		break
	fi
done
test_pass

########################################
# create_luks
########################################

test_begin "create_luks: basic luks"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
create_luks new_id="luks_root" name="root" id="part_root"
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_match "^luks:" "${DISK_ID_TO_RESOLVABLE[luks_root]}"
assert_contains "rd.luks.uuid=" "${DISK_DRACUT_CMDLINE[*]}"

test_begin "create_luks: with device instead of id"
reset_disk_state
create_luks new_id="luks_dev" name="crypt" device="/dev/sda1"
assert_eq true "$USED_LUKS"

########################################
# create_dummy
########################################

test_begin "create_dummy: basic dummy"
reset_disk_state
create_dummy new_id="dummy1" device="/dev/sda"
assert_eq "device:/dev/sda" "${DISK_ID_TO_RESOLVABLE[dummy1]}"
assert_contains "action=create_dummy" "${DISK_ACTIONS[*]}"

########################################
# format
########################################

test_begin "format: ext4"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format id="part" type="ext4" label="root"
assert_contains "action=format" "${DISK_ACTIONS[*]}"

test_begin "format: btrfs sets flag"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format id="part" type="btrfs"
assert_eq true "$USED_BTRFS"

test_begin "format: bcachefs sets flag"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format id="part" type="bcachefs"
assert_eq true "$USED_BCACHEFS"

test_begin "format: invalid type rejected"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
out="$(format id="part" type="ntfs" 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

test_begin "format: all valid types accepted"
for ftype in bios efi swap ext4 btrfs bcachefs; do
	reset_disk_state
	create_gpt new_id="gpt" device="/dev/sda"
	create_partition new_id="part" id="gpt" size="remaining" type="linux"
	out="$(format id="part" type="$ftype" 2>&1)"; rc=$?
	if [[ $rc -ne 0 ]]; then
		test_fail "type=$ftype should be valid"
		break
	fi
done
test_pass

########################################
# format_zfs
########################################

test_begin "format_zfs: basic zfs"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format_zfs ids="part"
assert_eq true "$USED_ZFS"
assert_contains "action=format_zfs" "${DISK_ACTIONS[*]}"

test_begin "format_zfs: encrypt sets USED_ENCRYPTION"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format_zfs ids="part" encrypt=true
assert_eq true "$USED_ENCRYPTION"

test_begin "format_zfs: optional properties accepted"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
out="$(format_zfs ids="part" ashift=12 autotrim=on compress=zstd recordsize=128K 2>&1)"; rc=$?
assert_eq 0 "$rc" "zfs with optional properties should succeed"

########################################
# format_btrfs
########################################

test_begin "format_btrfs: basic btrfs"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format_btrfs ids="part"
assert_eq true "$USED_BTRFS"
assert_contains "action=format_btrfs" "${DISK_ACTIONS[*]}"

test_begin "format_btrfs: with optional args"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
out="$(format_btrfs ids="part" label="myfs" checksum=xxhash nodesize=32k 2>&1)"; rc=$?
assert_eq 0 "$rc"

########################################
# format_bcachefs
########################################

test_begin "format_bcachefs: basic bcachefs"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format_bcachefs ids="part"
assert_eq true "$USED_BCACHEFS"
assert_contains "action=format_bcachefs" "${DISK_ACTIONS[*]}"

test_begin "format_bcachefs: encrypt sets USED_ENCRYPTION"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format_bcachefs ids="part" encrypt=true
assert_eq true "$USED_ENCRYPTION"

test_begin "format_bcachefs: with many optional args"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
out="$(format_bcachefs ids="part" compress=zstd data_checksum=xxhash block_size=4k data_replicas=2 acl=true discard=true 2>&1)"; rc=$?
assert_eq 0 "$rc"

########################################
# expand_ids
########################################

test_begin "expand_ids: matches regex"
reset_disk_state
declare -gA DISK_ID_TO_UUID=([part_efi_dev0]="u1" [part_swap_dev0]="u2" [part_root_dev0]="u3" [gpt_dev0]="u4")
result="$(expand_ids "^part_.*_dev0$")"
assert_contains "part_efi_dev0" "$result"
assert_contains "part_swap_dev0" "$result"
assert_contains "part_root_dev0" "$result"
assert_not_contains "gpt_dev0" "$result"

test_begin "expand_ids: no matches returns empty"
reset_disk_state
declare -gA DISK_ID_TO_UUID=([part1]="u1")
result="$(expand_ids "^nonexistent")"
assert_eq "" "$result"

########################################
# create_classic_single_disk_layout: full integration
########################################

test_begin "create_classic_single_disk_layout: efi + swap + ext4"
reset_disk_state
create_classic_single_disk_layout swap=8GiB /dev/sda
assert_eq "part_efi" "$DISK_ID_EFI"
assert_eq "part_swap" "$DISK_ID_SWAP"
assert_eq "part_root" "$DISK_ID_ROOT"
assert_eq "ext4" "$DISK_ID_ROOT_TYPE"
assert_contains "defaults,noatime,errors=remount-ro,discard" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "create_classic_single_disk_layout: efi + no swap + btrfs"
reset_disk_state
create_classic_single_disk_layout swap=false root_fs=btrfs /dev/sda
assert_eq "part_efi" "$DISK_ID_EFI"
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)" "no swap expected"
assert_eq "part_root" "$DISK_ID_ROOT"
assert_eq "btrfs" "$DISK_ID_ROOT_TYPE"
assert_contains "compress-force=zstd" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "create_classic_single_disk_layout: bios boot type"
reset_disk_state
create_classic_single_disk_layout swap=4GiB type=bios /dev/sda
assert_eq "part_bios" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)" "no efi expected"

test_begin "create_classic_single_disk_layout: with luks"
reset_disk_state
create_classic_single_disk_layout swap=4GiB luks=true /dev/sda
assert_eq "part_luks_root" "$DISK_ID_ROOT"
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"

test_begin "create_classic_single_disk_layout: bcachefs root"
reset_disk_state
create_classic_single_disk_layout swap=4GiB root_fs=bcachefs /dev/sda
assert_eq "bcachefs" "$DISK_ID_ROOT_TYPE"
assert_eq "defaults,noatime" "$DISK_ID_ROOT_MOUNT_OPTS"

test_begin "create_classic_single_disk_layout: correct DISK_ACTIONS count"
reset_disk_state
create_classic_single_disk_layout swap=8GiB /dev/sda
# Should have: create_gpt, part_efi, part_swap, part_root, format_efi, format_swap, format_root = 7 actions
# Count semicolons (action delimiters)
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 7 "$action_count" "efi+swap+root = 7 disk actions"

test_begin "create_classic_single_disk_layout: no swap has 5 actions"
reset_disk_state
create_classic_single_disk_layout swap=false /dev/sda
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 5 "$action_count" "efi+root (no swap) = 5 disk actions"

test_begin "create_classic_single_disk_layout: luks adds 1 extra action"
reset_disk_state
create_classic_single_disk_layout swap=false luks=true /dev/sda
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 6 "$action_count" "efi+root+luks (no swap) = 6 disk actions"

########################################
# create_existing_partitions_layout
########################################

test_begin "create_existing_partitions_layout: efi default"
reset_disk_state
create_existing_partitions_layout swap="/dev/sda2" boot="/dev/sda1" /dev/sda3
assert_eq "part_efi" "$DISK_ID_EFI"
assert_eq "part_swap" "$DISK_ID_SWAP"
assert_eq "part_root" "$DISK_ID_ROOT"
assert_eq true "$NO_PARTITIONING_OR_FORMATTING"
assert_eq "" "$DISK_ID_ROOT_TYPE"

test_begin "create_existing_partitions_layout: bios type"
reset_disk_state
create_existing_partitions_layout swap=false boot="/dev/sda1" type=bios /dev/sda2
assert_eq "part_bios" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)"
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

test_begin "create_existing_partitions_layout: no swap"
reset_disk_state
create_existing_partitions_layout swap=false boot="/dev/sda1" /dev/sda2
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

########################################
# apply_disk_actions parsing
########################################

test_begin "apply_disk_actions: parses semicolon-delimited actions"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
# Setting summarize mode so apply_disk_actions doesn't try real disk ops
disk_action_summarize_only=true
declare -A summary_tree summary_name summary_hint summary_ptr summary_desc summary_depth_continues
DISK_ID_EFI="part_efi"
DISK_ID_ROOT="__unused__"
out="$(apply_disk_actions 2>&1)"; rc=$?
assert_eq 0 "$rc" "apply_disk_actions in summary mode should succeed"

test_summary
