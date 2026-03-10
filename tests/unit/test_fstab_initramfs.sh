#!/bin/bash
# Tests for generate_fstab, generate_initramfs, install_authorized_keys, enable_sshd
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

setup_device_resolution

# Override get_blkid_uuid_for_id to return predictable UUIDs
function get_blkid_uuid_for_id() {
	echo "uuid-for-$1"
}

# Override chmod
function chmod() { echo "STUB:chmod $*"; }

# Create temp dir for file writes
_TEST_OUTDIR="$(command mktemp -d)"

# Save original functions for sed-based path redirection
_ORIG_GENERATE_INITRAMFS="$(declare -f generate_initramfs)"
_ORIG_INSTALL_AUTH_KEYS="$(declare -f install_authorized_keys)"

########################################
# generate_fstab
########################################

test_begin "generate_fstab: EFI + ext4 root + swap produces 3 entries"
reset_disk_state
reset_chroot_state
IS_EFI=true
USED_ZFS=false
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE="ext4"
DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime"
DISK_ID_EFI="efi"
DISK_ID_SWAP="swap"
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
assert_eq 0 "$rc"
_fstab_content="$(command cat "$_fstab")"
assert_contains "UUID=uuid-for-root" "$_fstab_content"
assert_contains "UUID=uuid-for-efi" "$_fstab_content"
assert_contains "UUID=uuid-for-swap" "$_fstab_content"
command rm -f "$_fstab"

test_begin "generate_fstab: EFI + ext4 root without swap produces 2 entries"
reset_disk_state
reset_chroot_state
IS_EFI=true
USED_ZFS=false
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE="ext4"
DISK_ID_ROOT_MOUNT_OPTS="defaults"
DISK_ID_EFI="efi"
unset DISK_ID_SWAP
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
assert_eq 0 "$rc"
_fstab_content="$(command cat "$_fstab")"
assert_contains "UUID=uuid-for-root" "$_fstab_content"
assert_contains "UUID=uuid-for-efi" "$_fstab_content"
assert_not_contains "swap" "$_fstab_content"
command rm -f "$_fstab"

test_begin "generate_fstab: BIOS + ext4 root + swap"
reset_disk_state
reset_chroot_state
IS_EFI=false
USED_ZFS=false
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE="ext4"
DISK_ID_ROOT_MOUNT_OPTS="defaults"
DISK_ID_BIOS="bios"
DISK_ID_SWAP="swap"
unset DISK_ID_EFI
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
assert_eq 0 "$rc"
_fstab_content="$(command cat "$_fstab")"
assert_contains "UUID=uuid-for-root" "$_fstab_content"
assert_contains "UUID=uuid-for-bios" "$_fstab_content"
assert_contains "UUID=uuid-for-swap" "$_fstab_content"
command rm -f "$_fstab"

test_begin "generate_fstab: ZFS root skips root entry"
reset_disk_state
reset_chroot_state
IS_EFI=true
USED_ZFS=true
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE=""
DISK_ID_ROOT_MOUNT_OPTS=""
DISK_ID_EFI="efi"
unset DISK_ID_SWAP
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
assert_eq 0 "$rc"
_fstab_content="$(command cat "$_fstab")"
assert_not_contains "UUID=uuid-for-root" "$_fstab_content"
assert_contains "UUID=uuid-for-efi" "$_fstab_content"
command rm -f "$_fstab"

test_begin "generate_fstab: EFI mounts at /boot/efi"
reset_disk_state
reset_chroot_state
IS_EFI=true
USED_ZFS=false
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE="ext4"
DISK_ID_ROOT_MOUNT_OPTS="defaults"
DISK_ID_EFI="efi"
unset DISK_ID_SWAP
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
_fstab_content="$(command cat "$_fstab")"
assert_contains "/boot/efi" "$_fstab_content"
command rm -f "$_fstab"

test_begin "generate_fstab: BIOS mounts at /boot/bios"
reset_disk_state
reset_chroot_state
IS_EFI=false
USED_ZFS=false
DISK_ID_ROOT="root"
DISK_ID_ROOT_TYPE="ext4"
DISK_ID_ROOT_MOUNT_OPTS="defaults"
DISK_ID_BIOS="bios"
unset DISK_ID_EFI DISK_ID_SWAP
_fstab="$(command mktemp)"
FSTAB_FILE="$_fstab"
function add_fstab_entry() { echo "$1 $2 $3 $4 $5" >> "$FSTAB_FILE"; }
capture_output out rc generate_fstab
_fstab_content="$(command cat "$_fstab")"
assert_contains "/boot/bios" "$_fstab_content"
command rm -f "$_fstab"

########################################
# generate_initramfs
########################################

# For generate_initramfs, redirect file writes via sed
function run_generate_initramfs() {
	command mkdir -p "$_TEST_OUTDIR/boot"
	eval "$(echo "$_ORIG_GENERATE_INITRAMFS" | command sed "s|/boot/|$_TEST_OUTDIR/boot/|g; s|/usr/lib/|$_TEST_OUTDIR/usr/lib/|g; s|/tmp|$_TEST_OUTDIR/tmp|g")"
	command mkdir -p "$_TEST_OUTDIR/tmp"
	command mkdir -p "$_TEST_OUTDIR/usr/lib/dracut/modules.d"
	capture_output out rc generate_initramfs "$_TEST_OUTDIR/boot/initramfs.img"
	eval "$_ORIG_GENERATE_INITRAMFS"
}

test_begin "generate_initramfs: base case includes bash module"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_eq 0 "$rc"
assert_contains "STUB:dracut" "$out"
assert_contains "bash" "$out"
assert_contains "--zstd" "$out"
assert_contains "--no-hostonly" "$out"
assert_contains "--ro-mnt" "$out"
assert_contains "--force" "$out"

test_begin "generate_initramfs: USED_RAID adds mdraid module"
reset_disk_state
reset_chroot_state
USED_RAID=true; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "mdraid" "$out"

test_begin "generate_initramfs: USED_LUKS adds crypt modules"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=true; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "crypt" "$out"

test_begin "generate_initramfs: USED_BTRFS adds btrfs module"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=true; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "btrfs" "$out"

test_begin "generate_initramfs: USED_ZFS adds zfs module"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=true; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "zfs" "$out"

test_begin "generate_initramfs: USED_BCACHEFS adds bcachefs module"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=true
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "bcachefs" "$out"

test_begin "generate_initramfs: multiple modules combined"
reset_disk_state
reset_chroot_state
USED_RAID=true; USED_LUKS=true; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "mdraid" "$out"
assert_contains "crypt" "$out"

test_begin "generate_initramfs: kver extracted from readlink"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=false; SYSTEMD_INITRAMFS_SSHD=false
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "--kver 6.1.0-gentoo" "$out"

test_begin "generate_initramfs: SYSTEMD_INITRAMFS_SSHD clones dracut-sshd"
reset_disk_state
reset_chroot_state
USED_RAID=false; USED_LUKS=false; USED_BTRFS=false; USED_ZFS=false; USED_BCACHEFS=false
SYSTEMD=true; SYSTEMD_INITRAMFS_SSHD=true
function readlink() { echo "linux-6.1.0-gentoo"; }
run_generate_initramfs
assert_contains "STUB:git clone" "$out"
assert_contains "dracut-sshd" "$out"
assert_contains "systemd-networkd" "$out"

########################################
# install_authorized_keys
########################################

# Override for file-write redirection
function run_install_authorized_keys() {
	eval "$(echo "$_ORIG_INSTALL_AUTH_KEYS" | command sed "s|/root/|$_TEST_OUTDIR/root/|g")"
	# Pre-create the directories (mkdir_or_die is stubbed)
	command mkdir -p "$_TEST_OUTDIR/root/.ssh"
	capture_output out rc install_authorized_keys
	eval "$_ORIG_INSTALL_AUTH_KEYS"
}

test_begin "install_authorized_keys: non-empty keys creates file"
reset_disk_state
reset_chroot_state
ROOT_SSH_AUTHORIZED_KEYS="ssh-rsa AAAA..."
run_install_authorized_keys
assert_eq 0 "$rc"
assert_contains "authorized keys" "$out"

test_begin "install_authorized_keys: empty keys skips file creation"
reset_disk_state
reset_chroot_state
ROOT_SSH_AUTHORIZED_KEYS=""
run_install_authorized_keys
assert_eq 0 "$rc"
assert_not_contains "Adding authorized keys" "$out"

########################################
# enable_sshd
########################################

test_begin "enable_sshd: calls install and enable_service"
reset_disk_state
reset_chroot_state
SYSTEMD=true
capture_output out rc enable_sshd
assert_eq 0 "$rc"
assert_contains "STUB:install" "$out"
assert_contains "sshd_config" "$out"
assert_contains "STUB:systemctl enable sshd" "$out"

test_begin "enable_sshd: OpenRC uses rc-update"
reset_disk_state
reset_chroot_state
SYSTEMD=false
capture_output out rc enable_sshd
assert_eq 0 "$rc"
assert_contains "STUB:rc-update add sshd default" "$out"

# Cleanup
command rm -rf "$_TEST_OUTDIR"

test_summary
