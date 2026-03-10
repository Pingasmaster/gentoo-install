#!/bin/bash
# Tests for install_kernel, install_kernel_efi, install_kernel_bios
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

setup_device_resolution

# Override get_blkid_uuid_for_id for consistent cmdline
function get_blkid_uuid_for_id() { echo "uuid-for-$1"; }

# Override generate_initramfs to not require real kernel
function generate_initramfs() { echo "STUB:generate_initramfs $*"; }

# Override find to return kernel filename
function find() { echo "vmlinuz-6.1.0-gentoo"; }

# Override chmod
function chmod() { echo "STUB:chmod $*"; }

# Create temp dirs for file writes in install_kernel_efi/bios
_KERNEL_TEST_DIR="$(command mktemp -d)"
command mkdir -p "$_KERNEL_TEST_DIR/boot/efi"
command mkdir -p "$_KERNEL_TEST_DIR/boot/bios/syslinux"

# Save original functions
_ORIG_INSTALL_KERNEL_EFI="$(declare -f install_kernel_efi)"
_ORIG_INSTALL_KERNEL_BIOS="$(declare -f install_kernel_bios)"
_ORIG_INSTALL_KERNEL="$(declare -f install_kernel)"

function restore_kernel_funcs() {
	eval "$_ORIG_INSTALL_KERNEL_EFI"
	eval "$_ORIG_INSTALL_KERNEL_BIOS"
	# Restore install_kernel with /etc/ redirection
	eval "$(echo "$_ORIG_INSTALL_KERNEL" | command sed "s|/etc/|$_KERNEL_TEST_DIR/etc/|g")"
}

# Redirect /etc/ writes in install_kernel
command mkdir -p "$_KERNEL_TEST_DIR/etc/portage"
command touch "$_KERNEL_TEST_DIR/etc/portage/package.license"
eval "$(echo "$_ORIG_INSTALL_KERNEL" | command sed "s|/etc/|$_KERNEL_TEST_DIR/etc/|g")"

# Wrapper for install_kernel_efi with file write redirection
function run_install_kernel_efi() {
	eval "$(echo "$_ORIG_INSTALL_KERNEL_EFI" | command sed "s|/boot/efi/|$_KERNEL_TEST_DIR/boot/efi/|g; s|/boot/|/boot/|g")"
	capture_output out rc install_kernel_efi
	restore_kernel_funcs
}

# Wrapper for install_kernel_bios with file write redirection
function run_install_kernel_bios() {
	eval "$(echo "$_ORIG_INSTALL_KERNEL_BIOS" | command sed "s|/boot/bios/|$_KERNEL_TEST_DIR/boot/bios/|g")"
	capture_output out rc install_kernel_bios
	restore_kernel_funcs
}

########################################
# install_kernel: dispatch
########################################

test_begin "install_kernel: IS_EFI=true dispatches to EFI path"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
function install_kernel_efi() { echo "CALLED:install_kernel_efi"; }
function install_kernel_bios() { echo "CALLED:install_kernel_bios"; }
capture_output out rc install_kernel
assert_eq 0 "$rc"
assert_contains "CALLED:install_kernel_efi" "$out"
assert_not_contains "CALLED:install_kernel_bios" "$out"
restore_kernel_funcs

test_begin "install_kernel: IS_EFI=false dispatches to BIOS path"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
function install_kernel_efi() { echo "CALLED:install_kernel_efi"; }
function install_kernel_bios() { echo "CALLED:install_kernel_bios"; }
capture_output out rc install_kernel
assert_eq 0 "$rc"
assert_contains "CALLED:install_kernel_bios" "$out"
assert_not_contains "CALLED:install_kernel_efi" "$out"
restore_kernel_funcs

test_begin "install_kernel: installs linux-firmware"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
function install_kernel_efi() { echo "STUB:install_kernel_efi"; }
capture_output out rc install_kernel
assert_contains "STUB:emerge" "$out"
assert_contains "linux-firmware" "$out"
restore_kernel_funcs

########################################
# install_kernel_efi: non-RAID
########################################

test_begin "install_kernel_efi: non-RAID creates efibootmgr entry"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([efi]="gpt")
# mdadm --detail fails (non-RAID)
function mdadm() { return 1; }
# readlink -f for sysfs resolution
function readlink() {
	if [[ "$1" == "-f" ]]; then
		echo "/sys/class/block/sda"
	else
		echo "STUB:readlink $*"
	fi
}
# cat for partition number
function cat() {
	if [[ "${1-}" == */partition ]]; then
		echo "2"
	elif [[ $# -eq 0 ]]; then
		command cat
	else
		command cat "$@" 2>/dev/null || true
	fi
}
run_install_kernel_efi
assert_eq 0 "$rc"
assert_contains "STUB:efibootmgr" "$out"
assert_contains "--create" "$out"
assert_contains "gentoo" "$out"
assert_contains "vmlinuz.efi" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function readlink() { echo "STUB:readlink $*"; }
unset -f cat

test_begin "install_kernel_efi: copies kernel to /boot/efi"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([efi]="gpt")
function mdadm() { return 1; }
function readlink() {
	if [[ "$1" == "-f" ]]; then echo "/sys/class/block/sda"; else echo "STUB:readlink $*"; fi
}
function cat() {
	if [[ "${1-}" == */partition ]]; then echo "2"
	elif [[ $# -eq 0 ]]; then command cat
	else command cat "$@" 2>/dev/null || true; fi
}
run_install_kernel_efi
assert_contains "STUB:cp /boot/vmlinuz-6.1.0-gentoo" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function readlink() { echo "STUB:readlink $*"; }
unset -f cat

test_begin "install_kernel_efi: calls generate_initramfs"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([efi]="gpt")
function mdadm() { return 1; }
function readlink() {
	if [[ "$1" == "-f" ]]; then echo "/sys/class/block/sda"; else echo "STUB:readlink $*"; fi
}
function cat() {
	if [[ "${1-}" == */partition ]]; then echo "2"
	elif [[ $# -eq 0 ]]; then command cat
	else command cat "$@" 2>/dev/null || true; fi
}
run_install_kernel_efi
assert_contains "STUB:generate_initramfs" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function readlink() { echo "STUB:readlink $*"; }
unset -f cat

########################################
# install_kernel_efi: RAID
########################################

test_begin "install_kernel_efi: RAID creates entries per member"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([efi]="gpt")
function mdadm() {
	if [[ "$1" == "--detail" ]]; then
		echo "       0       8        1        0      active sync   /dev/sda1"
		echo "       1       8       17        1      active sync   /dev/sdb1"
		return 0
	fi
	echo "STUB:mdadm $*"
}
# Use real sed for member extraction
function sed() {
	if [[ "$1" == "-n" ]]; then
		command sed "$@"
	else
		echo "STUB:sed $*"
	fi
}
function cat() {
	if [[ $# -eq 0 ]]; then command cat
	else command cat "$@" 2>/dev/null || true; fi
}
run_install_kernel_efi
assert_eq 0 "$rc"
assert_contains "/dev/sda1" "$out"
assert_contains "/dev/sdb1" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function sed() { echo "STUB:sed $*"; }
unset -f cat

test_begin "install_kernel_efi: RAID with no members dies"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([efi]="gpt")
function mdadm() {
	if [[ "$1" == "--detail" ]]; then
		echo "No members found"
		return 0
	fi
	echo "STUB:mdadm $*"
}
function sed() {
	if [[ "$1" == "-n" ]]; then
		command sed "$@"
	else
		echo "STUB:sed $*"
	fi
}
function cat() {
	if [[ $# -eq 0 ]]; then command cat
	else command cat "$@" 2>/dev/null || true; fi
}
run_install_kernel_efi
assert_neq 0 "$rc"
assert_contains "no valid member disks" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function sed() { echo "STUB:sed $*"; }
unset -f cat

########################################
# install_kernel_bios
########################################

test_begin "install_kernel_bios: non-RAID installs syslinux and MBR"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([bios]="gpt")
function mdadm() { return 1; }
run_install_kernel_bios
assert_eq 0 "$rc"
assert_contains "STUB:syslinux" "$out"
assert_contains "STUB:dd" "$out"
assert_contains "gptmbr.bin" "$out"
function mdadm() { echo "STUB:mdadm $*"; }

test_begin "install_kernel_bios: copies kernel to /boot/bios"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([bios]="gpt")
function mdadm() { return 1; }
run_install_kernel_bios
assert_contains "STUB:cp /boot/vmlinuz-6.1.0-gentoo" "$out"
function mdadm() { echo "STUB:mdadm $*"; }

test_begin "install_kernel_bios: calls generate_initramfs"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([bios]="gpt")
function mdadm() { return 1; }
run_install_kernel_bios
assert_contains "STUB:generate_initramfs" "$out"
function mdadm() { echo "STUB:mdadm $*"; }

test_begin "install_kernel_bios: RAID installs MBR to each member parent"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI
USED_ZFS=false
DISK_DRACUT_CMDLINE=()
declare -gA DISK_ID_PART_TO_GPT_ID=([bios]="gpt")
function mdadm() {
	if [[ "$1" == "--detail" ]]; then
		echo "       0       8        1        0      active sync   /dev/sda1"
		echo "       1       8       17        1      active sync   /dev/sdb1"
		return 0
	fi
	echo "STUB:mdadm $*"
}
function sed() {
	if [[ "$1" == "-n" ]]; then
		command sed "$@"
	else
		echo "STUB:sed $*"
	fi
}
function lsblk() { echo "sda"; }
run_install_kernel_bios
assert_eq 0 "$rc"
assert_contains "STUB:dd" "$out"
function mdadm() { echo "STUB:mdadm $*"; }
function sed() { echo "STUB:sed $*"; }
function lsblk() { echo "STUB:lsblk"; }

# Cleanup
command rm -rf "$_KERNEL_TEST_DIR"

test_summary
