#!/bin/bash
# Tests for disk summary/tree display system
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# add_summary_entry
########################################

test_begin "add_summary_entry: basic entry stored"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP DISK_ID_ROOT
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "gpt1" "sda" "(gpt)" ""
assert_eq "sda" "${summary_name[gpt1]}"
assert_eq "(gpt)" "${summary_hint[gpt1]}"
assert_contains "gpt1" "${summary_tree[__root__]}"

test_begin "add_summary_entry: efi pointer assigned"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_EFI="part_efi"
unset DISK_ID_BIOS DISK_ID_SWAP
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "part_efi" "part" "(efi)" ""
assert_contains "efi" "${summary_ptr[part_efi]}"

test_begin "add_summary_entry: swap pointer assigned"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_SWAP="part_swap"
unset DISK_ID_BIOS DISK_ID_EFI
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "part_swap" "part" "(swap)" ""
assert_contains "swap" "${summary_ptr[part_swap]}"

test_begin "add_summary_entry: root pointer assigned"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
DISK_ID_ROOT="part_root"
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
add_summary_entry "__root__" "part_root" "part" "(linux)" ""
assert_contains "root" "${summary_ptr[part_root]}"

test_begin "add_summary_entry: multiple children"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "child1" "n1" "h1" "d1"
add_summary_entry "__root__" "child2" "n2" "h2" "d2"
add_summary_entry "__root__" "child3" "n3" "h3" "d3"
assert_contains "child1" "${summary_tree[__root__]}"
assert_contains "child2" "${summary_tree[__root__]}"
assert_contains "child3" "${summary_tree[__root__]}"

test_begin "add_summary_entry: nested children"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "gpt" "/dev/sda" "(gpt)" ""
add_summary_entry "gpt" "part1" "part" "(efi)" ""
add_summary_entry "gpt" "part2" "part" "(linux)" ""
assert_contains "gpt" "${summary_tree[__root__]}"
assert_contains "part1" "${summary_tree[gpt]}"
assert_contains "part2" "${summary_tree[gpt]}"

########################################
# summary_color_args
########################################

test_begin "summary_color_args: formats present args"
declare -A arguments=([size]="10GiB" [type]="efi")
result="$(summary_color_args size type)"
assert_contains "size" "$result"
assert_contains "10GiB" "$result"
assert_contains "type" "$result"
assert_contains "efi" "$result"

test_begin "summary_color_args: skips absent args"
declare -A arguments=([size]="10GiB")
result="$(summary_color_args size label)"
assert_contains "size" "$result"
assert_not_contains "label" "$result"

test_begin "summary_color_args: empty args"
declare -A arguments=()
result="$(summary_color_args size label)"
assert_eq "" "$result"

########################################
# print_summary_tree: integration with add_summary_entry
########################################

test_begin "print_summary_tree: flat tree"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
DISK_ID_ROOT="__unused__"
add_summary_entry "__root__" "dev1" "/dev/sda" "(gpt)" ""
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "/dev/sda" "$result"

test_begin "print_summary_tree: nested tree"
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
unset DISK_ID_BIOS DISK_ID_EFI DISK_ID_SWAP
DISK_ID_ROOT="part_root"
add_summary_entry "__root__" "gpt" "/dev/sda" "(gpt)" ""
add_summary_entry "gpt" "part_efi" "part" "(efi)" "size=1GiB"
add_summary_entry "gpt" "part_root" "part" "(linux)" "size=remaining"
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "/dev/sda" "$result"
assert_contains "part" "$result"

########################################
# Full disk layout summary integration
########################################

test_begin "summary integration: single disk efi+ext4 layout"
reset_disk_state
create_classic_single_disk_layout swap=8GiB root_fs=ext4 /dev/sda
# Run summary in summarize mode
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
# Should show the device and partitions
assert_contains "/dev/sda" "$result"

test_begin "summary integration: single disk btrfs layout"
reset_disk_state
create_classic_single_disk_layout swap=false root_fs=btrfs /dev/nvme0n1
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "/dev/nvme0n1" "$result"

test_begin "summary integration: luks layout"
reset_disk_state
create_classic_single_disk_layout swap=4GiB luks=true /dev/sda
disk_action_summarize_only=true
declare -A summary_tree=() summary_name=() summary_hint=() summary_ptr=() summary_desc=() summary_depth_continues=()
apply_disk_actions
depth=-1
result="$(print_summary_tree __root__ 2>&1)"
assert_contains "luks" "$result"

test_summary
