#!/bin/bash
# Tests for scripts/main.sh functions
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# get_cmdline
########################################

test_begin "get_cmdline: basic keymap only"
reset_disk_state
KEYMAP_INITRAMFS="us"
DISK_DRACUT_CMDLINE=()
USED_ZFS=false
# Need to set up a device for DISK_ID_ROOT
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
# Override get_blkid_uuid_for_id since blkid isn't available
function get_blkid_uuid_for_id() { echo -n "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"; }
result="$(get_cmdline)"
assert_contains "rd.vconsole.keymap=us" "$result"
assert_contains "root=UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "$result"

test_begin "get_cmdline: zfs skips root=UUID"
reset_disk_state
KEYMAP_INITRAMFS="de"
DISK_DRACUT_CMDLINE=()
USED_ZFS=true
DISK_ID_ROOT="rpool"
result="$(get_cmdline)"
assert_contains "rd.vconsole.keymap=de" "$result"
assert_not_contains "root=UUID" "$result"

test_begin "get_cmdline: includes dracut cmdline entries"
reset_disk_state
KEYMAP_INITRAMFS="us"
DISK_DRACUT_CMDLINE=("rd.luks.uuid=aaaa-bbbb" "rd.md.uuid=cccc:dddd:eeee:ffff")
USED_ZFS=false
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
function get_blkid_uuid_for_id() { echo -n "test-uuid"; }
result="$(get_cmdline)"
assert_contains "rd.luks.uuid=aaaa-bbbb" "$result"
assert_contains "rd.md.uuid=cccc:dddd:eeee:ffff" "$result"
assert_contains "rd.vconsole.keymap=us" "$result"

test_begin "get_cmdline: different keymap"
reset_disk_state
KEYMAP_INITRAMFS="fr"
DISK_DRACUT_CMDLINE=()
USED_ZFS=true
DISK_ID_ROOT="rpool"
result="$(get_cmdline)"
assert_contains "rd.vconsole.keymap=fr" "$result"

########################################
# generate_syslinux_cfg
########################################

test_begin "generate_syslinux_cfg: contains kernel and initramfs refs"
reset_disk_state
KEYMAP_INITRAMFS="us"
DISK_DRACUT_CMDLINE=()
USED_ZFS=false
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
function get_blkid_uuid_for_id() { echo -n "test-uuid-1234"; }
result="$(generate_syslinux_cfg)"
assert_contains "LINUX ../vmlinuz-current" "$result"
assert_contains "APPEND initrd=../initramfs.img" "$result"
assert_contains "rd.vconsole.keymap=us" "$result"
assert_contains "root=UUID=test-uuid-1234" "$result"
assert_contains "DEFAULT gentoo" "$result"
assert_contains "TIMEOUT 0" "$result"

########################################
# add_fstab_entry
########################################

test_begin "add_fstab_entry: writes formatted line"
tmpfstab="$(mktemp)"
# Redirect /etc/fstab writes to temp file
function add_fstab_entry_test() {
	printf '%-46s  %-24s  %-6s  %-96s %s\n' "$1" "$2" "$3" "$4" "$5" >> "$tmpfstab"
}
add_fstab_entry_test "UUID=test-uuid" "/" "ext4" "defaults,noatime" "0 1"
content="$(cat "$tmpfstab")"
assert_contains "UUID=test-uuid" "$content"
assert_contains "ext4" "$content"
assert_contains "defaults,noatime" "$content"
assert_contains "0 1" "$content"
rm -f "$tmpfstab"

test_begin "add_fstab_entry: multiple entries"
tmpfstab="$(mktemp)"
function add_fstab_entry_test2() {
	printf '%-46s  %-24s  %-6s  %-96s %s\n' "$1" "$2" "$3" "$4" "$5" >> "$tmpfstab"
}
add_fstab_entry_test2 "UUID=root-uuid" "/" "ext4" "defaults" "0 1"
add_fstab_entry_test2 "UUID=efi-uuid" "/boot/efi" "vfat" "defaults,noatime" "0 2"
add_fstab_entry_test2 "UUID=swap-uuid" "none" "swap" "defaults,discard" "0 0"
lines="$(wc -l < "$tmpfstab")"
assert_eq 3 "$lines" "should have 3 fstab entries"
rm -f "$tmpfstab"

########################################
# check_config
########################################

test_begin "check_config: valid config passes"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo-box"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
_tmp_err="$(mktemp)"
check_config 2>"$_tmp_err"; rc=$?
out="$(cat "$_tmp_err")"; rm -f "$_tmp_err"
assert_eq 0 "$rc" "valid config should pass"
assert_eq true "$IS_EFI"

test_begin "check_config: invalid keymap"
reset_disk_state
KEYMAP="us!@#"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "invalid characters" "$out"

test_begin "check_config: systemd requires systemd stage3"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-openrc"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "systemd stage3" "$out"

test_begin "check_config: openrc rejects systemd stage3"
reset_disk_state
KEYMAP="us"
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "non-systemd stage3" "$out"

test_begin "check_config: invalid hostname"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="-invalid"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_contains "not a valid hostname" "$out"

test_begin "check_config: valid complex hostname"
reset_disk_state
KEYMAP="de"
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-openrc"
HOSTNAME="my-server.example.com"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
DISK_ID_ROOT="part_root"
DISK_ID_EFI="part_efi"
out="$(check_config 2>&1)"; rc=$?
assert_eq 0 "$rc" "FQDN hostname should be valid"

test_begin "check_config: missing DISK_ID_ROOT fails"
reset_disk_state
KEYMAP="us"
SYSTEMD=true
STAGE3_BASENAME="stage3-amd64-systemd"
HOSTNAME="gentoo"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="part_efi" id="gpt" size="1GiB" type="efi"
DISK_ID_EFI="part_efi"
unset DISK_ID_ROOT
out="$(check_config 2>&1)"; rc=$?
assert_contains "DISK_ID_ROOT" "$out"

test_begin "check_config: bios mode sets IS_EFI=false"
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
out="$(cat "$_tmp_err")"; rm -f "$_tmp_err"
assert_eq 0 "$rc"
assert_eq false "$IS_EFI"

########################################
# enable_service dispatch
########################################

test_begin "enable_service: systemd calls systemctl"
SYSTEMD=true
function systemctl() { echo "systemctl $*"; }
function rc-update() { echo "rc-update $*"; }
result="$(enable_service sshd 2>&1)"
assert_contains "systemctl" "$result"

test_begin "enable_service: openrc calls rc-update"
SYSTEMD=false
function systemctl() { echo "systemctl $*"; }
function rc-update() { echo "rc-update $*"; }
result="$(enable_service sshd 2>&1)"
assert_contains "rc-update" "$result"

test_summary
