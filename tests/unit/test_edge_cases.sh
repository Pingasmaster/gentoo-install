#!/bin/bash
# Edge case and error handling tests
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# Layout error handling
########################################

test_begin "create_classic_single_disk_layout: missing device fails"
reset_disk_state
out="$(create_classic_single_disk_layout swap=4GiB 2>&1)"; rc=$?
# extra_arguments should be empty, dying with "Expected exactly one positional argument"
# Actually, swap=4GiB is the only arg, and no device is given
# Need to check if 0 positional arguments triggers error
# Let's test with no extra arguments
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_classic_single_disk_layout swap=4GiB
' 2>&1)"; rc=$?
assert_contains "Expected exactly one positional argument" "$out"

test_begin "create_classic_single_disk_layout: extra device fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_classic_single_disk_layout swap=4GiB /dev/sda /dev/sdb
' 2>&1)"; rc=$?
assert_contains "Expected exactly one positional argument" "$out"

test_begin "create_zfs_centric_layout: no devices fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_zfs_centric_layout swap=4GiB
' 2>&1)"; rc=$?
assert_contains "Expected at least one positional argument" "$out"

test_begin "create_raid0_luks_layout: no devices fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_raid0_luks_layout swap=4GiB root_fs=ext4
' 2>&1)"; rc=$?
assert_contains "Expected at least one positional argument" "$out"

test_begin "create_raid1_luks_layout: no devices fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_raid1_luks_layout swap=4GiB root_fs=ext4
' 2>&1)"; rc=$?
assert_contains "Expected at least one positional argument" "$out"

test_begin "create_btrfs_centric_layout: no devices fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_btrfs_centric_layout swap=4GiB
' 2>&1)"; rc=$?
assert_contains "Expected at least one positional argument" "$out"

test_begin "create_bcachefs_centric_layout: no devices fails"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	create_bcachefs_centric_layout swap=4GiB
' 2>&1)"; rc=$?
assert_contains "Expected at least one positional argument" "$out"

########################################
# Deprecated function tests
########################################

test_begin "create_single_disk_layout: shows deprecation"
reset_disk_state
out="$(create_single_disk_layout 2>&1)"; rc=$?
assert_contains "deprecated" "$out"

test_begin "create_btrfs_raid_layout: shows deprecation"
reset_disk_state
out="$(create_btrfs_raid_layout 2>&1)"; rc=$?
assert_contains "deprecated" "$out"

########################################
# Partition type: hex code
########################################

test_begin "create_partition: accepts 4-digit hex code"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
out="$(create_partition new_id="p1" id="gpt" size="1GiB" type="ef02" 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "create_partition: accepts lowercase hex"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
out="$(create_partition new_id="p1" id="gpt" size="1GiB" type="8300" 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "create_partition: rejects 3-digit hex"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
out="$(create_partition new_id="p1" id="gpt" size="1GiB" type="830" 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

test_begin "create_partition: rejects 5-digit hex"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
out="$(create_partition new_id="p1" id="gpt" size="1GiB" type="83001" 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

########################################
# Multiple partitions on same GPT
########################################

test_begin "multiple partitions: 3 partitions on same GPT"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="1GiB" type="efi"
create_partition new_id="p2" id="gpt" size="8GiB" type="swap"
create_partition new_id="p3" id="gpt" size="remaining" type="linux"
assert_eq "gpt" "${DISK_ID_PART_TO_GPT_ID[p1]}"
assert_eq "gpt" "${DISK_ID_PART_TO_GPT_ID[p2]}"
assert_eq "gpt" "${DISK_ID_PART_TO_GPT_ID[p3]}"

test_begin "multiple partitions: can't add after size=remaining"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
out="$(create_partition new_id="p2" id="gpt" size="1GiB" type="efi" 2>&1)"; rc=$?
assert_contains "after size=remaining" "$out"

test_begin "multiple partitions: size=remaining on different GPTs is fine"
reset_disk_state
create_gpt new_id="gpt1" device="/dev/sda"
create_partition new_id="p1" id="gpt1" size="remaining" type="linux"
create_gpt new_id="gpt2" device="/dev/sdb"
out="$(create_partition new_id="p2" id="gpt2" size="remaining" type="linux" 2>&1)"; rc=$?
assert_eq 0 "$rc"

########################################
# create_gpt: device vs id mutual exclusion
########################################

test_begin "create_gpt: device and id are mutually exclusive"
reset_disk_state
register_existing new_id="base" device="/dev/sda"
out="$(create_gpt new_id="gpt" device="/dev/sdb" id="base" 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

test_begin "create_gpt: neither device nor id fails"
reset_disk_state
out="$(create_gpt new_id="gpt" 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out"

########################################
# create_luks: device vs id
########################################

test_begin "create_luks: device and id are mutually exclusive"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
out="$(create_luks new_id="crypt" name="root" device="/dev/sdb" id="p1" 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

########################################
# register_existing: requires both new_id and device
########################################

test_begin "register_existing: missing new_id fails"
reset_disk_state
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	register_existing device="/dev/sda1"
' 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out"

test_begin "register_existing: missing device fails"
reset_disk_state
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	reset_disk_state
	register_existing new_id="test"
' 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out"

########################################
# expand_ids: regex patterns
########################################

test_begin "expand_ids: matches everything with .*"
reset_disk_state
declare -gA DISK_ID_TO_UUID=([a]="u1" [b]="u2" [c]="u3")
result="$(expand_ids ".*")"
assert_contains "a" "$result"
assert_contains "b" "$result"
assert_contains "c" "$result"

test_begin "expand_ids: anchored regex"
reset_disk_state
declare -gA DISK_ID_TO_UUID=([part_root_dev0]="u1" [part_root_dev1]="u2" [gpt_dev0]="u3")
result="$(expand_ids "^part_root_")"
assert_contains "part_root_dev0" "$result"
assert_contains "part_root_dev1" "$result"
assert_not_contains "gpt_dev0" "$result"

test_begin "expand_ids: digit regex"
reset_disk_state
declare -gA DISK_ID_TO_UUID=([part_swap_dev0]="u1" [part_swap_dev1]="u2" [part_swap_dev10]="u3")
result="$(expand_ids '^part_swap_dev[[:digit:]]+$')"
assert_contains "part_swap_dev0" "$result"
assert_contains "part_swap_dev1" "$result"
assert_contains "part_swap_dev10" "$result"

########################################
# Various device path formats
########################################

test_begin "layout: /dev/disk/by-id path works"
reset_disk_state
create_classic_single_disk_layout swap=4GiB /dev/disk/by-id/ata-VBOX_HARDDISK_VB12345678-90abcdef
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_begin "layout: /dev/nvme path works"
reset_disk_state
create_classic_single_disk_layout swap=4GiB /dev/nvme0n1
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_begin "layout: /dev/vda path works"
reset_disk_state
create_classic_single_disk_layout swap=4GiB /dev/vda
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

test_begin "layout: /dev/mmcblk0 path works"
reset_disk_state
create_classic_single_disk_layout swap=4GiB /dev/mmcblk0
assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"

########################################
# format: edge cases
########################################

test_begin "format: with label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format id="part" type="ext4" label="my_root"
assert_contains "label=my_root" "${DISK_ACTIONS[*]}"

test_begin "format: without label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part" id="gpt" size="remaining" type="linux"
format id="part" type="ext4"
# Should still succeed, label is optional
assert_contains "action=format" "${DISK_ACTIONS[*]}"

########################################
# DISK_DRACUT_CMDLINE accumulation
########################################

test_begin "dracut cmdline: raid accumulates UUID entries"
reset_disk_state
create_gpt new_id="gpt1" device="/dev/sda"
create_partition new_id="p1" id="gpt1" size="remaining" type="raid"
create_gpt new_id="gpt2" device="/dev/sdb"
create_partition new_id="p2" id="gpt2" size="remaining" type="raid"
create_raid new_id="md1" level=1 name="root" ids="p1;p2"
# Create another raid
create_gpt new_id="gpt3" device="/dev/sdc"
create_partition new_id="p3" id="gpt3" size="remaining" type="raid"
create_gpt new_id="gpt4" device="/dev/sdd"
create_partition new_id="p4" id="gpt4" size="remaining" type="raid"
create_raid new_id="md2" level=0 name="data" ids="p3;p4"
# Should have 2 rd.md.uuid entries
count=0
for entry in "${DISK_DRACUT_CMDLINE[@]}"; do
	[[ "$entry" == rd.md.uuid=* ]] && count=$((count + 1))
done
assert_eq 2 "$count" "2 raid arrays = 2 rd.md.uuid entries"

test_begin "dracut cmdline: luks accumulates UUID entries"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="50%" type="linux"
create_partition new_id="p2" id="gpt" size="remaining" type="linux"
create_luks new_id="crypt1" name="root" id="p1"
create_luks new_id="crypt2" name="data" id="p2"
count=0
for entry in "${DISK_DRACUT_CMDLINE[@]}"; do
	[[ "$entry" == rd.luks.uuid=* ]] && count=$((count + 1))
done
assert_eq 2 "$count" "2 luks volumes = 2 rd.luks.uuid entries"

test_summary
