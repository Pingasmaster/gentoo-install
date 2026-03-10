#!/bin/bash
# Extended tests for bcachefs_centric_layout: LUKS+bcachefs combo, multi-device, etc.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# create_bcachefs_centric_layout: LUKS combination
########################################

test_begin "bcachefs: LUKS + bcachefs native encrypt fails"
reset_disk_state
# die in test_env returns 1 instead of exiting, so the function continues.
# We test that it at least outputs the error message.
out="$(create_bcachefs_centric_layout swap=false encrypt=true luks=true /dev/sda 2>&1)" || true
assert_contains "Cannot use both LUKS and bcachefs native encryption" "$out"

test_begin "bcachefs: LUKS only (no native encrypt) succeeds"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda
assert_eq true "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_eq true "$USED_BCACHEFS"
assert_eq "luks_dev0" "$DISK_ID_ROOT"

test_begin "bcachefs: native encrypt only (no LUKS) succeeds"
reset_disk_state
create_bcachefs_centric_layout swap=false encrypt=true /dev/sda
assert_eq false "$USED_LUKS"
assert_eq true "$USED_ENCRYPTION"
assert_eq true "$USED_BCACHEFS"
assert_eq "part_root_dev0" "$DISK_ID_ROOT"

test_begin "bcachefs: neither encrypt nor LUKS succeeds"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq false "$USED_LUKS"
assert_eq false "$USED_ENCRYPTION"
assert_eq true "$USED_BCACHEFS"

########################################
# create_bcachefs_centric_layout: multi-disk with LUKS
########################################

test_begin "bcachefs: multi-disk with LUKS creates luks volumes for all"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda /dev/sdb /dev/sdc
assert_eq true "$USED_LUKS"
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev0] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev1] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[luks_dev2] ]] && echo true || echo false)"
assert_eq "luks_dev0" "$DISK_ID_ROOT"

test_begin "bcachefs: multi-disk without LUKS uses dummy devices"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda /dev/sdb /dev/sdc
assert_eq false "$USED_LUKS"
assert_eq true "$([[ -v DISK_ID_TO_UUID[root_dev1] ]] && echo true || echo false)"
assert_eq true "$([[ -v DISK_ID_TO_UUID[root_dev2] ]] && echo true || echo false)"

########################################
# create_bcachefs_centric_layout: BCACHEFS_DEVICE_IDS
########################################

test_begin "bcachefs: single disk sets BCACHEFS_DEVICE_IDS"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq true "$([[ -v BCACHEFS_DEVICE_IDS ]] && echo true || echo false)"
assert_contains "part_root_dev0" "$BCACHEFS_DEVICE_IDS"

test_begin "bcachefs: multi-disk BCACHEFS_DEVICE_IDS includes all"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda /dev/sdb
assert_contains "part_root_dev0" "$BCACHEFS_DEVICE_IDS"
assert_contains "root_dev1" "$BCACHEFS_DEVICE_IDS"

test_begin "bcachefs: multi-disk LUKS BCACHEFS_DEVICE_IDS has luks ids"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda /dev/sdb
assert_contains "luks_dev0" "$BCACHEFS_DEVICE_IDS"
assert_contains "luks_dev1" "$BCACHEFS_DEVICE_IDS"

########################################
# create_bcachefs_centric_layout: boot type
########################################

test_begin "bcachefs: efi boot (default)"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq "part_efi_dev0" "$DISK_ID_EFI"
assert_eq false "$([[ -v DISK_ID_BIOS ]] && echo true || echo false)"

test_begin "bcachefs: bios boot"
reset_disk_state
create_bcachefs_centric_layout swap=false type=bios /dev/sda
assert_eq "part_bios_dev0" "$DISK_ID_BIOS"
assert_eq false "$([[ -v DISK_ID_EFI ]] && echo true || echo false)"

########################################
# create_bcachefs_centric_layout: swap
########################################

test_begin "bcachefs: with swap"
reset_disk_state
create_bcachefs_centric_layout swap=4GiB /dev/sda
assert_eq "part_swap_dev0" "$DISK_ID_SWAP"

test_begin "bcachefs: no swap"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq false "$([[ -v DISK_ID_SWAP ]] && echo true || echo false)"

########################################
# create_bcachefs_centric_layout: mount opts
########################################

test_begin "bcachefs: mount opts are defaults,noatime"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
assert_eq "defaults,noatime" "$DISK_ID_ROOT_MOUNT_OPTS"

########################################
# create_bcachefs_centric_layout: format options
########################################

test_begin "bcachefs: compress option"
reset_disk_state
create_bcachefs_centric_layout swap=false compress=zstd /dev/sda 2>/dev/null
assert_contains "compress=zstd" "${DISK_ACTIONS[*]}"

test_begin "bcachefs: data_replicas option"
reset_disk_state
create_bcachefs_centric_layout swap=false data_replicas=2 /dev/sda 2>/dev/null
assert_contains "data_replicas=2" "${DISK_ACTIONS[*]}"

test_begin "bcachefs: all optional args accepted"
reset_disk_state
create_bcachefs_centric_layout swap=false \
	compress=zstd bg_compress=lz4 errors=continue \
	data_checksum=xxhash metadata_checksum=crc32c \
	str_hash=siphash block_size=4k btree_node_size=256k \
	data_replicas=2 metadata_replicas=2 \
	acl=true discard=true \
	/dev/sda 2>/dev/null; rc=$?
assert_eq 0 "$rc"

########################################
# create_bcachefs_centric_layout: action count
########################################

test_begin "bcachefs: action count single disk no swap"
reset_disk_state
create_bcachefs_centric_layout swap=false /dev/sda
# gpt + part_efi + part_root + format_efi + format_bcachefs = 5
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 5 "$action_count" "bcachefs single no-swap = 5"

test_begin "bcachefs: action count single disk with swap"
reset_disk_state
create_bcachefs_centric_layout swap=4GiB /dev/sda
# gpt + part_efi + part_swap + part_root + format_efi + format_swap + format_bcachefs = 7
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 7 "$action_count" "bcachefs single with-swap = 7"

test_begin "bcachefs: action count single disk with LUKS no swap"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda
# gpt + part_efi + part_root + luks_dev0 + format_efi + format_bcachefs = 6
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 6 "$action_count" "bcachefs single luks no-swap = 6"

test_begin "bcachefs: action count 2 disks with LUKS"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda /dev/sdb
# gpt + part_efi + part_root + luks_dev0 + luks_dev1 + format_efi + format_bcachefs = 7
action_count=0
for item in "${DISK_ACTIONS[@]}"; do
	[[ "$item" == ";" ]] && action_count=$((action_count + 1))
done
assert_eq 7 "$action_count" "bcachefs 2-disk luks no-swap = 7"

########################################
# Summary integration
########################################

test_begin "bcachefs layout: summary tree renders"
reset_disk_state
create_bcachefs_centric_layout swap=4GiB /dev/sda
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "/dev/sda" "$result"
assert_contains "bcachefs" "$result"

test_begin "bcachefs layout: luks+multi-disk summary tree"
reset_disk_state
create_bcachefs_centric_layout swap=false luks=true /dev/sda /dev/sdb
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "luks" "$result"
assert_contains "bcachefs" "$result"

test_summary
