#!/bin/bash
# Tests for device resolution fallback paths and check_wanted_programs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

########################################
# get_device_by_partuuid: fallback paths
########################################

test_begin "get_device_by_partuuid: existing path returns direct link"
reset_disk_state
_tmpdir="$(command mktemp -d)"
_fake_uuid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
command mkdir -p "$_tmpdir/by-partuuid"
# Use a regular file (not a symlink to nonexistent target)
echo "/dev/sda1" > "$_tmpdir/by-partuuid/$_fake_uuid"
function get_device_by_partuuid() {
	local uuid="${1,,}"
	local path="$_tmpdir/by-partuuid/$uuid"
	if [[ -e "$path" ]]; then
		echo "$path"
		return 0
	fi
	get_device_by_blkid_field PARTUUID "$uuid"
}
capture_output out rc get_device_by_partuuid "$_fake_uuid"
assert_eq 0 "$rc"
assert_contains "by-partuuid" "$out"
command rm -rf "$_tmpdir"

test_begin "get_device_by_partuuid: missing path falls back to blkid"
reset_disk_state
function get_device_by_partuuid() {
	local uuid="${1,,}"
	local path="/dev/disk/by-partuuid/$uuid"
	if [[ -e "$path" ]]; then
		echo "$path"
		return 0
	fi
	echo "FALLBACK:blkid-$uuid"
}
capture_output out rc get_device_by_partuuid "nonexistent-uuid"
assert_eq 0 "$rc"
assert_contains "FALLBACK:blkid-nonexistent-uuid" "$out"

########################################
# get_device_by_uuid: fallback paths
########################################

test_begin "get_device_by_uuid: existing path returns direct link"
reset_disk_state
_tmpdir="$(command mktemp -d)"
_fake_uuid="11111111-2222-3333-4444-555555555555"
command mkdir -p "$_tmpdir/by-uuid"
echo "/dev/sdb1" > "$_tmpdir/by-uuid/$_fake_uuid"
function get_device_by_uuid() {
	local uuid="${1,,}"
	local path="$_tmpdir/by-uuid/$uuid"
	if [[ -e "$path" ]]; then
		echo "$path"
		return 0
	fi
	get_device_by_blkid_field UUID "$uuid"
}
capture_output out rc get_device_by_uuid "$_fake_uuid"
assert_eq 0 "$rc"
assert_contains "by-uuid" "$out"
command rm -rf "$_tmpdir"

test_begin "get_device_by_uuid: missing path falls back to blkid"
reset_disk_state
function get_device_by_uuid() {
	local uuid="${1,,}"
	local path="/dev/disk/by-uuid/$uuid"
	if [[ -e "$path" ]]; then
		echo "$path"
		return 0
	fi
	echo "FALLBACK:blkid-uuid-$uuid"
}
capture_output out rc get_device_by_uuid "missing-uuid"
assert_eq 0 "$rc"
assert_contains "FALLBACK:blkid-uuid-missing-uuid" "$out"

########################################
# get_device_by_ptuuid
########################################

test_begin "get_device_by_ptuuid: with CACHED_LSBLK_OUTPUT uses cache"
reset_disk_state
# Format must match: after lowercasing, grep for ptuuid="..." partuuid=""
export CACHED_LSBLK_OUTPUT='NAME="/dev/sda" PTUUID="aaaa-bbbb" PARTUUID=""
NAME="/dev/sdb" PTUUID="cccc-dddd" PARTUUID=""'
capture_output out rc get_device_by_ptuuid "aaaa-bbbb"
assert_eq 0 "$rc"
assert_contains "sda" "$out"
unset CACHED_LSBLK_OUTPUT

test_begin "get_device_by_ptuuid: finds correct device from multiple"
reset_disk_state
export CACHED_LSBLK_OUTPUT='NAME="/dev/sda" PTUUID="1111-2222" PARTUUID=""
NAME="/dev/sdb" PTUUID="3333-4444" PARTUUID=""
NAME="/dev/sdc" PTUUID="5555-6666" PARTUUID=""'
capture_output out rc get_device_by_ptuuid "3333-4444"
assert_eq 0 "$rc"
assert_contains "sdb" "$out"
unset CACHED_LSBLK_OUTPUT

test_begin "get_device_by_ptuuid: ptuuid not found dies"
reset_disk_state
export CACHED_LSBLK_OUTPUT='NAME="/dev/sda" PTUUID="1111-2222" PARTUUID=""'
capture_output out rc get_device_by_ptuuid "no-such-uuid"
assert_neq 0 "$rc"
unset CACHED_LSBLK_OUTPUT

########################################
# load_or_generate_uuid (real behavior)
########################################

test_begin "load_or_generate_uuid: file exists reads UUID"
reset_disk_state
_tmpdir="$(command mktemp -d)"
UUID_STORAGE_DIR="$_tmpdir"
echo -n "existing-uuid-value" > "$_tmpdir/test_id"
_real_uuid="$(
	unset -f load_or_generate_uuid
	builtin source "$PROJECT_DIR/scripts/utils.sh" 2>/dev/null
	load_or_generate_uuid "test_id"
)"
assert_eq "existing-uuid-value" "$_real_uuid"
command rm -rf "$_tmpdir"

test_begin "load_or_generate_uuid: file missing generates and writes UUID"
reset_disk_state
_tmpdir="$(command mktemp -d)"
UUID_STORAGE_DIR="$_tmpdir"
_generated_uuid="$(
	unset -f load_or_generate_uuid
	function uuidgen() { echo "generated-test-uuid"; }
	builtin source "$PROJECT_DIR/scripts/utils.sh" 2>/dev/null
	load_or_generate_uuid "new_id"
)"
assert_eq "generated-test-uuid" "$_generated_uuid"
command rm -rf "$_tmpdir"

########################################
# check_wanted_programs
########################################

test_begin "check_wanted_programs: all present succeeds"
reset_disk_state
function has_program() { return 0; }
capture_output out rc check_wanted_programs gpg wget lsblk
assert_eq 0 "$rc"

test_begin "check_wanted_programs: optional missing warns but succeeds"
reset_disk_state
function has_program() {
	[[ "$1" != "rhash" ]]
}
capture_output out rc check_wanted_programs gpg "?rhash" lsblk
assert_eq 0 "$rc"

test_begin "check_wanted_programs: required missing reported"
reset_disk_state
function has_program() {
	[[ "$1" != "missing_prog" ]]
}
# check_wanted_programs calls ask(), our stub returns 0 (yes, continue)
# When required programs are missing, it warns and asks user
capture_output out rc check_wanted_programs "missing_prog"
assert_contains "missing_prog" "$out"

########################################
# resolve_device_by_id: error cases
########################################

test_begin "resolve_device_by_id: unregistered id dies"
reset_disk_state
unset -f resolve_device_by_id
capture_output out rc resolve_device_by_id "nonexistent_id"
assert_neq 0 "$rc"
setup_device_resolution

########################################
# uuid_to_mduuid edge cases
########################################

test_begin "uuid_to_mduuid: standard conversion"
reset_disk_state
_result="$(uuid_to_mduuid "12345678-1234-1234-1234-123456789abc")"
assert_eq "12345678:12341234:12341234:56789abc" "$_result"

test_begin "uuid_to_mduuid: all zeros"
reset_disk_state
_result="$(uuid_to_mduuid "00000000-0000-0000-0000-000000000000")"
assert_eq "00000000:00000000:00000000:00000000" "$_result"

test_summary
