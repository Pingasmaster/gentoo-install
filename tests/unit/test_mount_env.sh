#!/bin/bash
# Tests for mount_efivars, mount_by_id, mount_root, gentoo_umount, gentoo_chroot, extract_stage3
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

setup_device_resolution

# Override mkdir to prevent permission errors
function mkdir() { echo "STUB:mkdir $*"; }

########################################
# mount_efivars
########################################

test_begin "mount_efivars: already mounted skips mount"
reset_disk_state
function mountpoint() { return 0; }
capture_output out rc mount_efivars
assert_eq 0 "$rc"
assert_not_contains "STUB:mount" "$out"
function mountpoint() { return 1; }

test_begin "mount_efivars: not mounted calls mount -t efivarfs"
reset_disk_state
function mountpoint() { return 1; }
capture_output out rc mount_efivars
assert_eq 0 "$rc"
assert_contains "STUB:mount -t efivarfs" "$out"

test_begin "mount_efivars: mount failure dies"
reset_disk_state
function mountpoint() { return 1; }
function mount() { return 1; }
capture_output out rc mount_efivars
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function mount() { echo "STUB:mount $*"; }

########################################
# mount_by_id
########################################

test_begin "mount_by_id: already mounted skips mount"
reset_disk_state
function mountpoint() { return 0; }
capture_output out rc mount_by_id "root" "/mnt/root"
assert_eq 0 "$rc"
assert_not_contains "STUB:mount" "$out"
function mountpoint() { return 1; }

test_begin "mount_by_id: not mounted resolves and mounts"
reset_disk_state
function mountpoint() { return 1; }
capture_output out rc mount_by_id "myroot" "/mnt/root"
assert_eq 0 "$rc"
assert_contains "STUB:mount $_FAKE_DEV_DIR/myroot /mnt/root" "$out"

test_begin "mount_by_id: mount failure dies"
reset_disk_state
function mountpoint() { return 1; }
function mount() { return 1; }
capture_output out rc mount_by_id "myroot" "/mnt/root"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function mount() { echo "STUB:mount $*"; }

########################################
# mount_root
########################################

test_begin "mount_root: ZFS not mounted dies"
reset_disk_state
reset_chroot_state
USED_ZFS=true
USED_BCACHEFS=false
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 1; }
capture_output out rc mount_root
assert_neq 0 "$rc"
assert_contains "Expected zfs to be mounted" "$out"

test_begin "mount_root: bcachefs with device IDs, not mounted, resolves and mounts"
reset_disk_state
reset_chroot_state
USED_ZFS=false
USED_BCACHEFS=true
USED_ENCRYPTION=false
USED_LUKS=false
BCACHEFS_DEVICE_IDS="bc1;bc2"
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 1; }
capture_output out rc mount_root
assert_eq 0 "$rc"
assert_contains "STUB:mount -t bcachefs $_FAKE_DEV_DIR/bc1:$_FAKE_DEV_DIR/bc2" "$out"

test_begin "mount_root: bcachefs with native encryption pipes key"
reset_disk_state
reset_chroot_state
USED_ZFS=false
USED_BCACHEFS=true
USED_ENCRYPTION=true
USED_LUKS=false
BCACHEFS_DEVICE_IDS="bc1"
ROOT_MOUNTPOINT="/tmp/test_mount"
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
function mountpoint() { return 1; }
capture_output out rc mount_root
assert_eq 0 "$rc"
assert_contains "STUB:bcachefs mount" "$out"

test_begin "mount_root: bcachefs already mounted skips"
reset_disk_state
reset_chroot_state
USED_ZFS=false
USED_BCACHEFS=true
BCACHEFS_DEVICE_IDS="bc1"
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 0; }
capture_output out rc mount_root
assert_eq 0 "$rc"
assert_not_contains "STUB:mount" "$out"
assert_not_contains "STUB:bcachefs" "$out"
function mountpoint() { return 1; }

test_begin "mount_root: standard delegates to mount_by_id"
reset_disk_state
reset_chroot_state
USED_ZFS=false
USED_BCACHEFS=false
DISK_ID_ROOT="myroot"
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 1; }
capture_output out rc mount_root
assert_eq 0 "$rc"
assert_contains "STUB:mount $_FAKE_DEV_DIR/myroot" "$out"

########################################
# gentoo_umount
########################################

test_begin "gentoo_umount: mounted calls umount -R -l"
reset_disk_state
reset_chroot_state
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 0; }
capture_output out rc gentoo_umount
assert_eq 0 "$rc"
assert_contains "STUB:umount -R -l /tmp/test_mount" "$out"
function mountpoint() { return 1; }

test_begin "gentoo_umount: not mounted is no-op"
reset_disk_state
reset_chroot_state
ROOT_MOUNTPOINT="/tmp/test_mount"
function mountpoint() { return 1; }
capture_output out rc gentoo_umount
assert_eq 0 "$rc"
assert_not_contains "STUB:umount" "$out"

########################################
# gentoo_chroot
########################################

test_begin "gentoo_chroot: already in chroot dies"
reset_disk_state
reset_chroot_state
EXECUTED_IN_CHROOT=true
function bind_repo_dir() { :; }
capture_output out rc gentoo_chroot "/mnt/gentoo" /bin/true
assert_neq 0 "$rc"
assert_contains "Already in chroot" "$out"
unset EXECUTED_IN_CHROOT

test_begin "gentoo_chroot: copies resolv.conf"
reset_disk_state
reset_chroot_state
unset EXECUTED_IN_CHROOT
function bind_repo_dir() { :; }
function cache_lsblk_output() { :; }
function exec() { echo "STUB:exec $*"; }
capture_output out rc gentoo_chroot "/mnt/gentoo" /bin/true
assert_contains "STUB:install" "$out"
assert_contains "resolv.conf" "$out"
unset -f exec

test_begin "gentoo_chroot: mounts virtual filesystems"
reset_disk_state
reset_chroot_state
unset EXECUTED_IN_CHROOT
function bind_repo_dir() { :; }
function cache_lsblk_output() { :; }
function exec() { echo "STUB:exec $*"; }
capture_output out rc gentoo_chroot "/mnt/gentoo" /bin/true
assert_contains "STUB:mount" "$out"
unset -f exec

test_begin "gentoo_chroot: calls bind_repo_dir"
reset_disk_state
reset_chroot_state
unset EXECUTED_IN_CHROOT
function bind_repo_dir() { echo "CALLED:bind_repo_dir"; }
function cache_lsblk_output() { :; }
function exec() { echo "STUB:exec $*"; }
capture_output out rc gentoo_chroot "/mnt/gentoo" /bin/true
assert_contains "CALLED:bind_repo_dir" "$out"
unset -f exec

########################################
# extract_stage3
########################################

test_begin "extract_stage3: empty CURRENT_STAGE3 dies"
reset_disk_state
reset_chroot_state
CURRENT_STAGE3=""
function mount_root() { :; }
capture_output out rc extract_stage3
assert_neq 0 "$rc"
assert_contains "CURRENT_STAGE3 is not set" "$out"

test_begin "extract_stage3: missing stage3 file dies"
reset_disk_state
reset_chroot_state
CURRENT_STAGE3="stage3-amd64-20230101.tar.xz"
TMP_DIR="/tmp/nonexistent_test_dir"
function mount_root() { :; }
capture_output out rc extract_stage3
assert_neq 0 "$rc"
assert_contains "does not exist" "$out"

########################################
# enable_service
########################################

test_begin "enable_service: systemd calls systemctl enable"
reset_disk_state
SYSTEMD=true
capture_output out rc enable_service "sshd"
assert_eq 0 "$rc"
assert_contains "STUB:systemctl enable sshd" "$out"

test_begin "enable_service: OpenRC calls rc-update add"
reset_disk_state
SYSTEMD=false
capture_output out rc enable_service "sshd"
assert_eq 0 "$rc"
assert_contains "STUB:rc-update add sshd default" "$out"

########################################
# touch_or_die
########################################

test_begin "touch_or_die: creates file and chmods"
reset_disk_state
_tmpfile="$(mktemp)"
capture_output out rc touch_or_die 0644 "$_tmpfile"
assert_eq 0 "$rc"
command rm -f "$_tmpfile"

test_summary
