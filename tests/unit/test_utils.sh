#!/bin/bash
# Tests for scripts/utils.sh functions
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# uuid_to_mduuid
########################################

test_begin "uuid_to_mduuid: standard UUID"
result="$(uuid_to_mduuid "12345678-abcd-ef01-2345-6789abcdef01")"
assert_eq "12345678:abcdef01:23456789:abcdef01" "$result"

test_begin "uuid_to_mduuid: uppercase UUID"
result="$(uuid_to_mduuid "AABBCCDD-EEFF-0011-2233-445566778899")"
assert_eq "aabbccdd:eeff0011:22334455:66778899" "$result"

test_begin "uuid_to_mduuid: already lowercase"
result="$(uuid_to_mduuid "aabbccdd-eeff-0011-2233-445566778899")"
assert_eq "aabbccdd:eeff0011:22334455:66778899" "$result"

test_begin "uuid_to_mduuid: mixed case"
result="$(uuid_to_mduuid "AaBbCcDd-EeFf-0011-2233-445566778899")"
assert_eq "aabbccdd:eeff0011:22334455:66778899" "$result"

########################################
# shorten_device
########################################

test_begin "shorten_device: strips /dev/disk/by-id/ prefix"
result="$(shorten_device "/dev/disk/by-id/ata-VBOX_HARDDISK_VBxxxxxxxx")"
assert_eq "ata-VBOX_HARDDISK_VBxxxxxxxx" "$result"

test_begin "shorten_device: returns unchanged if no prefix"
result="$(shorten_device "/dev/sda")"
assert_eq "/dev/sda" "$result"

test_begin "shorten_device: empty string"
result="$(shorten_device "")"
assert_eq "" "$result"

test_begin "shorten_device: partial prefix"
result="$(shorten_device "/dev/disk/by-uuid/xxxx")"
assert_eq "/dev/disk/by-uuid/xxxx" "$result"

########################################
# create_resolve_entry / create_resolve_entry_device
########################################

test_begin "create_resolve_entry: stores type:arg in lowercase"
declare -gA DISK_ID_TO_RESOLVABLE=()
create_resolve_entry "test_id" "partuuid" "ABCD-1234"
assert_eq "partuuid:abcd-1234" "${DISK_ID_TO_RESOLVABLE[test_id]}"

test_begin "create_resolve_entry_device: stores device:path"
declare -gA DISK_ID_TO_RESOLVABLE=()
create_resolve_entry_device "test_id" "/dev/sda1"
assert_eq "device:/dev/sda1" "${DISK_ID_TO_RESOLVABLE[test_id]}"

########################################
# parse_arguments
########################################

test_begin "parse_arguments: basic key=value"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "foo=bar" "baz=qux"
assert_eq "bar" "${arguments[foo]}"

test_begin "parse_arguments: value with equals sign"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "key=val=ue"
assert_eq "val=ue" "${arguments[key]}"

test_begin "parse_arguments: extra positional arguments"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "key=val" "/dev/sda"
assert_eq "val" "${arguments[key]}"
assert_eq "/dev/sda" "${extra_arguments[0]}"

test_begin "parse_arguments: mandatory argument present"
unset arguments; declare -A arguments
extra_arguments=()
known_arguments=('+name')
out="$(parse_arguments "name=test" 2>&1)"; rc=$?
assert_eq 0 "$rc" "mandatory arg present should succeed"

test_begin "parse_arguments: mandatory argument missing"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	unset arguments; declare -A arguments
	extra_arguments=()
	known_arguments=("+name")
	parse_arguments "other=test"
' 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out" "should mention missing mandatory"

test_begin "parse_arguments: unknown argument rejected"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	unset arguments; declare -A arguments
	extra_arguments=()
	known_arguments=("+name")
	parse_arguments "name=ok" "bogus=bad"
' 2>&1)"; rc=$?
assert_contains "Unknown argument" "$out"

test_begin "parse_arguments: at-least-one-of (device|id) with device"
unset arguments; declare -A arguments
extra_arguments=()
known_arguments=('+device|id')
out="$(parse_arguments "device=/dev/sda" 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "parse_arguments: at-least-one-of (device|id) missing both"
out="$(bash -c '
	source "'"$(dirname "${BASH_SOURCE[0]}")"'/test_env.sh"
	unset arguments; declare -A arguments
	extra_arguments=()
	known_arguments=("+device|id")
	parse_arguments "name=test"
' 2>&1)"; rc=$?
assert_contains "Missing mandatory" "$out"

########################################
# only_one_of
########################################

test_begin "only_one_of: one present is OK"
declare -A arguments=([device]="/dev/sda")
out="$(only_one_of device id 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "only_one_of: none present is OK"
declare -A arguments=()
out="$(only_one_of device id 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "only_one_of: both present fails"
declare -A arguments=([device]="/dev/sda" [id]="gpt")
out="$(only_one_of device id 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

########################################
# verify_option
########################################

test_begin "verify_option: valid option"
declare -A arguments=([type]="efi")
out="$(verify_option type bios efi swap 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_option: invalid option"
declare -A arguments=([type]="ntfs")
out="$(verify_option type bios efi swap 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

########################################
# verify_existing_id
########################################

test_begin "verify_existing_id: existing id passes"
declare -A arguments=([id]="gpt")
declare -gA DISK_ID_TO_UUID=([gpt]="some-uuid")
out="$(verify_existing_id id 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_existing_id: missing id fails"
declare -A arguments=([id]="nonexistent")
declare -gA DISK_ID_TO_UUID=([gpt]="some-uuid")
out="$(verify_existing_id id 2>&1)"; rc=$?
assert_contains "not found" "$out"

########################################
# verify_existing_unique_ids
########################################

test_begin "verify_existing_unique_ids: single valid id"
declare -A arguments=([ids]="gpt")
declare -gA DISK_ID_TO_UUID=([gpt]="some-uuid")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_existing_unique_ids: multiple valid ids"
declare -A arguments=([ids]="part1;part2")
declare -gA DISK_ID_TO_UUID=([part1]="uuid1" [part2]="uuid2")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_existing_unique_ids: duplicate ids fail"
declare -A arguments=([ids]="part1;part1")
declare -gA DISK_ID_TO_UUID=([part1]="uuid1")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_contains "duplicate" "$out"

test_begin "verify_existing_unique_ids: unknown id fails"
declare -A arguments=([ids]="part1;unknown")
declare -gA DISK_ID_TO_UUID=([part1]="uuid1")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_contains "unknown identifier" "$out"

test_begin "verify_existing_unique_ids: empty ids fail"
declare -A arguments=([ids]="")
declare -gA DISK_ID_TO_UUID=()
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_contains "at least one" "$out"

########################################
# countdown (non-interactive output test)
########################################

test_begin "countdown: output format"
result="$(countdown "Starting in " 3 2>&1)"
assert_contains "Starting in " "$result"
assert_contains "3" "$result"
assert_contains "2" "$result"
assert_contains "1" "$result"

########################################
# for_line_in
########################################

test_begin "for_line_in: processes each line"
tmpfile="$(mktemp)"
printf "line1\nline2\nline3\n" > "$tmpfile"
collected=()
function collect_line() { collected+=("$1"); }
for_line_in "$tmpfile" collect_line
assert_eq 3 "${#collected[@]}" "should have 3 lines"
assert_eq "line1" "${collected[0]}"
assert_eq "line3" "${collected[2]}"
rm -f "$tmpfile"

########################################
# has_program
########################################

test_begin "has_program: bash exists"
has_program "bash" ""; rc=$?
assert_eq 0 "$rc"

test_begin "has_program: nonexistent program"
has_program "definitely_not_a_real_program_xyz" ""; rc=$?
assert_eq 1 "$rc"

test_begin "has_program: checkfile absolute path exists"
has_program "ignored" "/bin/bash"; rc=$?
assert_eq 0 "$rc"

test_begin "has_program: checkfile absolute path missing"
has_program "ignored" "/nonexistent/path/xyz"; rc=$?
assert_eq 1 "$rc"

########################################
# get_device_by_luks_name
########################################

test_begin "get_device_by_luks_name: returns /dev/mapper/name"
result="$(get_device_by_luks_name "root")"
assert_eq "/dev/mapper/root" "$result"

test_begin "get_device_by_luks_name: with dashes"
result="$(get_device_by_luks_name "luks-abcd-1234")"
assert_eq "/dev/mapper/luks-abcd-1234" "$result"

test_summary
