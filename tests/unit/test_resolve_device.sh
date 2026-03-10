#!/bin/bash
# Tests for device resolution functions (resolve_device_by_id and helpers)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# resolve_device_by_id: device type
########################################

test_begin "resolve_device_by_id: type=device resolves directly"
reset_disk_state
# We need to override canonicalize_device since realpath won't work for fake devs
function canonicalize_device() { echo -n "$1"; }
DISK_ID_TO_RESOLVABLE=([mydev]="device:/dev/sda1")
result="$(resolve_device_by_id mydev)"
assert_eq "/dev/sda1" "$result"

test_begin "resolve_device_by_id: type=luks resolves to /dev/mapper/name"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
DISK_ID_TO_RESOLVABLE=([myluks]="luks:root")
result="$(resolve_device_by_id myluks)"
assert_eq "/dev/mapper/root" "$result"

test_begin "resolve_device_by_id: type=luks with dashes"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
DISK_ID_TO_RESOLVABLE=([myluks]="luks:luks-abc-123")
result="$(resolve_device_by_id myluks)"
assert_eq "/dev/mapper/luks-abc-123" "$result"

test_begin "resolve_device_by_id: unknown id fails"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
DISK_ID_TO_RESOLVABLE=()
out="$(resolve_device_by_id "nonexistent" 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "no table entry" "$out"

test_begin "resolve_device_by_id: unknown type fails"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
DISK_ID_TO_RESOLVABLE=([bad]="faketype:arg")
out="$(resolve_device_by_id "bad" 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "unknown type" "$out"

########################################
# resolve_device_by_id: partuuid type
########################################

test_begin "resolve_device_by_id: type=partuuid uses get_device_by_partuuid"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
function get_device_by_partuuid() { echo -n "/dev/sda2"; }
DISK_ID_TO_RESOLVABLE=([mypart]="partuuid:aabb-ccdd")
result="$(resolve_device_by_id mypart)"
assert_eq "/dev/sda2" "$result"

########################################
# resolve_device_by_id: ptuuid type
########################################

test_begin "resolve_device_by_id: type=ptuuid uses get_device_by_ptuuid"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
function get_device_by_ptuuid() { echo -n "/dev/sda"; }
DISK_ID_TO_RESOLVABLE=([mygpt]="ptuuid:1234-5678")
result="$(resolve_device_by_id mygpt)"
assert_eq "/dev/sda" "$result"

########################################
# resolve_device_by_id: uuid type
########################################

test_begin "resolve_device_by_id: type=uuid uses get_device_by_uuid"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
function get_device_by_uuid() { echo -n "/dev/sdb1"; }
DISK_ID_TO_RESOLVABLE=([myuuid]="uuid:aaaa-bbbb-cccc")
result="$(resolve_device_by_id myuuid)"
assert_eq "/dev/sdb1" "$result"

########################################
# resolve_device_by_id: mdadm type
########################################

test_begin "resolve_device_by_id: type=mdadm uses get_device_by_mdadm_uuid"
reset_disk_state
function canonicalize_device() { echo -n "$1"; }
function get_device_by_mdadm_uuid() { echo -n "/dev/md/root"; }
DISK_ID_TO_RESOLVABLE=([mymd]="mdadm:12345678-abcd-ef01-2345-6789abcdef01")
result="$(resolve_device_by_id mymd)"
assert_eq "/dev/md/root" "$result"

########################################
# get_device_by_luks_name
########################################

test_begin "get_device_by_luks_name: simple name"
result="$(get_device_by_luks_name "cryptroot")"
assert_eq "/dev/mapper/cryptroot" "$result"

test_begin "get_device_by_luks_name: name with underscores"
result="$(get_device_by_luks_name "luks_root_0")"
assert_eq "/dev/mapper/luks_root_0" "$result"

test_begin "get_device_by_luks_name: empty name"
result="$(get_device_by_luks_name "")"
assert_eq "/dev/mapper/" "$result"

########################################
# create_resolve_entry: type lowercasing
########################################

test_begin "create_resolve_entry: lowercases arg"
declare -gA DISK_ID_TO_RESOLVABLE=()
create_resolve_entry "test_id" "partuuid" "AABB-CCDD-EEFF"
assert_eq "partuuid:aabb-ccdd-eeff" "${DISK_ID_TO_RESOLVABLE[test_id]}"

test_begin "create_resolve_entry: preserves type case"
declare -gA DISK_ID_TO_RESOLVABLE=()
create_resolve_entry "test_id" "PARTUUID" "aabb"
assert_eq "PARTUUID:aabb" "${DISK_ID_TO_RESOLVABLE[test_id]}"

test_begin "create_resolve_entry_device: does not lowercase device path"
declare -gA DISK_ID_TO_RESOLVABLE=()
create_resolve_entry_device "test_id" "/dev/SDA1"
assert_eq "device:/dev/SDA1" "${DISK_ID_TO_RESOLVABLE[test_id]}"

########################################
# uuid_to_mduuid: edge cases
########################################

test_begin "uuid_to_mduuid: all zeros"
result="$(uuid_to_mduuid "00000000-0000-0000-0000-000000000000")"
assert_eq "00000000:00000000:00000000:00000000" "$result"

test_begin "uuid_to_mduuid: all f's"
result="$(uuid_to_mduuid "ffffffff-ffff-ffff-ffff-ffffffffffff")"
assert_eq "ffffffff:ffffffff:ffffffff:ffffffff" "$result"

########################################
# Integration: create_gpt sets ptuuid resolution
########################################

test_begin "integration: create_gpt + resolve uses ptuuid type"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
assert_match "^ptuuid:" "${DISK_ID_TO_RESOLVABLE[gpt]}"

test_begin "integration: create_partition sets partuuid resolution"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part1" id="gpt" size="1GiB" type="efi"
assert_match "^partuuid:" "${DISK_ID_TO_RESOLVABLE[part1]}"

test_begin "integration: create_raid sets mdadm resolution"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="10GiB" type="raid"
create_raid new_id="md" level=1 name="root" ids="p1"
assert_match "^mdadm:" "${DISK_ID_TO_RESOLVABLE[md]}"

test_begin "integration: create_luks sets luks resolution"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
create_luks new_id="crypt" name="root" id="p1"
assert_match "^luks:" "${DISK_ID_TO_RESOLVABLE[crypt]}"

test_begin "integration: register_existing sets device resolution"
reset_disk_state
register_existing new_id="ext" device="/dev/nvme0n1p3"
assert_eq "device:/dev/nvme0n1p3" "${DISK_ID_TO_RESOLVABLE[ext]}"

test_summary
