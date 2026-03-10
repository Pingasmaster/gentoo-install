#!/bin/bash
# Extended tests for check_config and check_encryption_key
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

# Helper to set up a minimal valid config
function setup_valid_config() {
	reset_disk_state
	KEYMAP="us"
	SYSTEMD=true
	STAGE3_BASENAME="stage3-amd64-systemd"
	HOSTNAME="gentoo"
	create_gpt new_id="gpt" device="/dev/sda"
	create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_ROOT="part_root"
	DISK_ID_EFI="part_efi"
}

########################################
# check_config: hostname validation
########################################

test_begin "check_config: single-char hostname valid"
setup_valid_config
HOSTNAME="a"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: hostname with numbers valid"
setup_valid_config
HOSTNAME="server01"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: hostname with inner dash valid"
setup_valid_config
HOSTNAME="my-server"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: hostname ending with dash invalid"
setup_valid_config
HOSTNAME="server-"
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: hostname starting with dash invalid"
setup_valid_config
HOSTNAME="-server"
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: hostname with underscore invalid"
setup_valid_config
HOSTNAME="my_server"
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: hostname with spaces invalid"
setup_valid_config
HOSTNAME="my server"
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: empty hostname invalid"
setup_valid_config
HOSTNAME=""
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: FQDN hostname valid"
setup_valid_config
HOSTNAME="web01.dc1.example.com"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: hostname with dots but trailing dot invalid"
setup_valid_config
HOSTNAME="web01."
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

########################################
# check_config: keymap validation
########################################

test_begin "check_config: keymap with letters and numbers valid"
setup_valid_config
KEYMAP="us"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: keymap with dashes valid"
setup_valid_config
KEYMAP="de-latin1"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: empty keymap valid"
setup_valid_config
KEYMAP=""
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: keymap with special chars invalid"
setup_valid_config
KEYMAP='us;echo pwned'
out="$(check_config 2>&1)"; rc=$?
assert_contains "invalid characters" "$out"

test_begin "check_config: keymap with spaces invalid"
setup_valid_config
KEYMAP="us de"
out="$(check_config 2>&1)"; rc=$?
assert_contains "invalid characters" "$out"

test_begin "check_config: keymap with dot invalid"
setup_valid_config
KEYMAP="us.utf8"
out="$(check_config 2>&1)"; rc=$?
assert_contains "invalid characters" "$out"

########################################
# check_config: SYSTEMD / stage3 validation
########################################

test_begin "check_config: systemd=true with openrc stage3 fails"
setup_valid_config
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-openrc-20230101T170000Z"
out="$(check_config 2>&1)"; rc=$?
assert_contains "systemd stage3" "$out"

test_begin "check_config: systemd=false with systemd stage3 fails"
setup_valid_config
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-systemd-20230101T170000Z"
out="$(check_config 2>&1)"; rc=$?
assert_contains "non-systemd stage3" "$out"

test_begin "check_config: systemd=false with openrc stage3 passes"
setup_valid_config
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-openrc-20230101T170000Z"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

test_begin "check_config: systemd=true with systemd stage3 passes"
setup_valid_config
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd-mergedusr-20230101T170000Z"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"

########################################
# check_config: boot partition validation
########################################

test_begin "check_config: missing both DISK_ID_EFI and DISK_ID_BIOS fails"
setup_valid_config
unset DISK_ID_EFI
unset DISK_ID_BIOS
out="$(check_config 2>&1)"; rc=$?
assert_contains "DISK_ID_EFI or DISK_ID_BIOS" "$out"

test_begin "check_config: DISK_ID_EFI set without UUID fails"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="nonexistent_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "Missing uuid for DISK_ID_EFI" "$out"

test_begin "check_config: DISK_ID_SWAP set without UUID fails"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
DISK_ID_SWAP="nonexistent_swap"
out="$(check_config 2>&1)"; rc=$?
assert_contains "Missing uuid for DISK_ID_SWAP" "$out"

test_begin "check_config: DISK_ID_ROOT set without UUID fails"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
DISK_ID_ROOT="nonexistent_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "Missing uuid for DISK_ID_ROOT" "$out"

########################################
# check_config: IS_EFI flag
########################################

test_begin "check_config: EFI mode sets IS_EFI=true"
setup_valid_config
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq true "$IS_EFI"

test_begin "check_config: BIOS mode sets IS_EFI=false"
reset_disk_state
KEYMAP="us"
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-openrc"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_bios" id="gpt" size="1GiB" type="bios"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_BIOS="part_bios"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"
assert_eq false "$IS_EFI"

########################################
# check_encryption_key
########################################

test_begin "check_encryption_key: valid key passes"
export GENTOO_INSTALL_ENCRYPTION_KEY="mysecretpassword"
_tmp_err="$(mktemp)"
check_encryption_key 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"
unset GENTOO_INSTALL_ENCRYPTION_KEY

test_begin "check_encryption_key: short key fails"
export GENTOO_INSTALL_ENCRYPTION_KEY="short"
out="$(check_encryption_key 2>&1)"; rc=$?
assert_contains "at least 8 characters" "$out"
unset GENTOO_INSTALL_ENCRYPTION_KEY

test_begin "check_encryption_key: exactly 8 chars passes"
export GENTOO_INSTALL_ENCRYPTION_KEY="12345678"
_tmp_err="$(mktemp)"
check_encryption_key 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"
unset GENTOO_INSTALL_ENCRYPTION_KEY

test_begin "check_encryption_key: 7 chars fails"
export GENTOO_INSTALL_ENCRYPTION_KEY="1234567"
out="$(check_encryption_key 2>&1)"; rc=$?
assert_contains "at least 8 characters" "$out"
unset GENTOO_INSTALL_ENCRYPTION_KEY

test_begin "check_encryption_key: key with special chars passes"
export GENTOO_INSTALL_ENCRYPTION_KEY='p@$$w0rd!#%'
_tmp_err="$(mktemp)"
check_encryption_key 2>"$_tmp_err"; rc=$?
rm -f "$_tmp_err"
assert_eq 0 "$rc"
unset GENTOO_INSTALL_ENCRYPTION_KEY

test_summary
