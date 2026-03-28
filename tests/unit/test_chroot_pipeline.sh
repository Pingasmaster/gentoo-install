#!/bin/bash
# Tests for main_install_gentoo_in_chroot — the main chrooted installation pipeline
# Tests verify correct command sequence under different configurations
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

setup_device_resolution

# Override heavy sub-functions with call-logging wrappers
function configure_base_system() { log_call "configure_base_system"; }
function configure_portage()     { log_call "configure_portage"; }
function install_kernel()        { log_call "install_kernel"; }
function generate_fstab()        { log_call "generate_fstab"; }
function install_authorized_keys() { log_call "install_authorized_keys"; }
function enable_sshd()           { log_call "enable_sshd"; }
function enable_chronyd()        { log_call "enable_chronyd"; }
function enable_cron()           { log_call "enable_cron"; }
function enable_syslogger()      { log_call "enable_syslogger"; }
function mount_efivars()         { log_call "mount_efivars"; }
function mount_by_id()           { log_call "mount_by_id $*"; }
function maybe_exec()            { :; }
function env_update()            { :; }

# Source/profile stubs
function source() {
	if [[ "$1" == "/etc/profile" ]]; then
		return 0
	fi
	builtin source "$@"
}

# Override chmod to not fail on nonexistent files
function chmod() { echo "STUB:chmod $*"; }

# Override command for 'command -v' checks
function command() {
	if [[ "$1" == "-v" ]]; then
		return 0
	fi
	builtin command "$@"
}

# Create temp dir structure for /etc/ file writes
_PIPELINE_ETCDIR="$(command mktemp -d)"
command mkdir -p "$_PIPELINE_ETCDIR/portage/repos.conf"
command mkdir -p "$_PIPELINE_ETCDIR/portage/package.use"
command mkdir -p "$_PIPELINE_ETCDIR/portage/patches/sys-kernel/gentoo-kernel"
command mkdir -p "$_PIPELINE_ETCDIR/systemd/network"
command touch "$_PIPELINE_ETCDIR/portage/make.conf"

# Save original function for sed-based redirection
_ORIG_PIPELINE="$(declare -f main_install_gentoo_in_chroot)"

########################################
# Helper: run the pipeline with /etc/ redirection
########################################
function run_pipeline() {
	reset_call_log
	# Redefine the function with /etc/ paths redirected to temp dir
	eval "$(echo "$_ORIG_PIPELINE" | command sed "s|/etc/|$_PIPELINE_ETCDIR/|g")"
	capture_output out rc main_install_gentoo_in_chroot
	# Restore original (for next test)
	eval "$_ORIG_PIPELINE"
}

########################################
# Core flow
########################################

test_begin "pipeline: clears root password first"
reset_chroot_state
run_pipeline
assert_eq 0 "$rc"
assert_contains "STUB:passwd -d root" "$out"

test_begin "pipeline: calls emerge-webrsync"
reset_chroot_state
run_pipeline
assert_contains "STUB:emerge-webrsync" "$out"

test_begin "pipeline: calls configure_base_system"
reset_chroot_state
run_pipeline
assert_call_log_contains "configure_base_system"

test_begin "pipeline: calls configure_portage"
reset_chroot_state
run_pipeline
assert_call_log_contains "configure_portage"

test_begin "pipeline: calls install_kernel"
reset_chroot_state
run_pipeline
assert_call_log_contains "install_kernel"

test_begin "pipeline: calls generate_fstab"
reset_chroot_state
run_pipeline
assert_call_log_contains "generate_fstab"

test_begin "pipeline: calls install_authorized_keys"
reset_chroot_state
run_pipeline
assert_call_log_contains "install_authorized_keys"

test_begin "pipeline: installs gentoolkit"
reset_chroot_state
run_pipeline
assert_contains "gentoolkit" "$out"

########################################
# EFI vs BIOS mount
########################################

test_begin "pipeline: IS_EFI=true mounts efivars and EFI partition"
reset_chroot_state
IS_EFI=true
DISK_ID_EFI="efi"
run_pipeline
assert_call_log_contains "mount_efivars"
assert_call_log_contains "mount_by_id efi /boot/efi"

test_begin "pipeline: IS_EFI=false mounts BIOS partition"
reset_chroot_state
IS_EFI=false
DISK_ID_BIOS="bios"
unset DISK_ID_EFI 2>/dev/null || true
run_pipeline
assert_call_log_not_contains "mount_efivars"
assert_call_log_contains "mount_by_id bios /boot/bios"

########################################
# RAID
########################################

test_begin "pipeline: USED_RAID=true installs mdadm"
reset_chroot_state
USED_RAID=true
run_pipeline
assert_contains "sys-fs/mdadm" "$out"

test_begin "pipeline: USED_RAID=false skips mdadm"
reset_chroot_state
USED_RAID=false
run_pipeline
assert_not_contains "sys-fs/mdadm" "$out"

########################################
# LUKS
########################################

test_begin "pipeline: USED_LUKS=true installs cryptsetup"
reset_chroot_state
USED_LUKS=true
run_pipeline
assert_contains "sys-fs/cryptsetup" "$out"

test_begin "pipeline: USED_LUKS=true + SYSTEMD rebuilds systemd with cryptsetup USE"
reset_chroot_state
USED_LUKS=true
SYSTEMD=true
run_pipeline
assert_contains "sys-apps/systemd" "$out"

test_begin "pipeline: USED_LUKS=false skips cryptsetup"
reset_chroot_state
USED_LUKS=false
run_pipeline
assert_not_contains "sys-fs/cryptsetup" "$out"

########################################
# Btrfs
########################################

test_begin "pipeline: USED_BTRFS=true installs btrfs-progs"
reset_chroot_state
USED_BTRFS=true
run_pipeline
assert_contains "sys-fs/btrfs-progs" "$out"

test_begin "pipeline: USED_BTRFS=false skips btrfs-progs"
reset_chroot_state
USED_BTRFS=false
run_pipeline
assert_not_contains "sys-fs/btrfs-progs" "$out"

########################################
# Bcachefs
########################################

test_begin "pipeline: USED_BCACHEFS=true installs bcachefs-tools"
reset_chroot_state
USED_BCACHEFS=true
run_pipeline
assert_contains "sys-fs/bcachefs-tools" "$out"

test_begin "pipeline: USED_BCACHEFS=true forces kernel from source"
reset_chroot_state
USED_BCACHEFS=true
KERNEL_TYPE="bin"
run_pipeline
assert_contains "gentoo-kernel" "$out"
assert_not_contains "gentoo-kernel-bin" "$out"

########################################
# ZFS
########################################

test_begin "pipeline: USED_ZFS=true installs zfs packages"
reset_chroot_state
USED_ZFS=true
run_pipeline
assert_contains "sys-fs/zfs" "$out"
assert_contains "sys-fs/zfs-kmod" "$out"

test_begin "pipeline: USED_ZFS=true + SYSTEMD enables zfs services"
reset_chroot_state
USED_ZFS=true
SYSTEMD=true
run_pipeline
assert_contains "STUB:systemctl enable zfs.target" "$out"
assert_contains "STUB:systemctl enable zfs-import-cache" "$out"
assert_contains "STUB:systemctl enable zfs-mount" "$out"

test_begin "pipeline: USED_ZFS=true + OpenRC enables zfs services"
reset_chroot_state
USED_ZFS=true
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-openrc"
run_pipeline
assert_contains "STUB:rc-update add zfs-import boot" "$out"
assert_contains "STUB:rc-update add zfs-mount boot" "$out"

########################################
# Kernel type
########################################

test_begin "pipeline: KERNEL_TYPE=source installs gentoo-kernel"
reset_chroot_state
KERNEL_TYPE="source"
run_pipeline
assert_contains "gentoo-kernel" "$out"

test_begin "pipeline: KERNEL_TYPE=bin installs gentoo-kernel-bin"
reset_chroot_state
KERNEL_TYPE="bin"
USED_BCACHEFS=false
run_pipeline
assert_contains "gentoo-kernel-bin" "$out"

########################################
# Git portage sync
########################################

test_begin "pipeline: PORTAGE_SYNC_TYPE=git writes repos.conf"
reset_chroot_state
PORTAGE_SYNC_TYPE="git"
PORTAGE_GIT_MIRROR="https://github.com/gentoo-mirror/gentoo.git"
PORTAGE_GIT_FULL_HISTORY=false
run_pipeline
# Check the file was written to temp dir
_reposconf="$(command cat "$_PIPELINE_ETCDIR/portage/repos.conf/gentoo.conf" 2>/dev/null || true)"
assert_contains "sync-type = git" "$_reposconf"
assert_contains "sync-depth = 1" "$_reposconf"

test_begin "pipeline: PORTAGE_GIT_FULL_HISTORY=true sets sync-depth=0"
reset_chroot_state
PORTAGE_SYNC_TYPE="git"
PORTAGE_GIT_MIRROR="https://github.com/gentoo-mirror/gentoo.git"
PORTAGE_GIT_FULL_HISTORY=true
run_pipeline
_reposconf="$(command cat "$_PIPELINE_ETCDIR/portage/repos.conf/gentoo.conf" 2>/dev/null || true)"
assert_contains "sync-depth = 0" "$_reposconf"

test_begin "pipeline: PORTAGE_SYNC_TYPE=rsync skips git config"
reset_chroot_state
PORTAGE_SYNC_TYPE="rsync"
# Clear any previous git config
command rm -f "$_PIPELINE_ETCDIR/portage/repos.conf/gentoo.conf" 2>/dev/null
run_pipeline
assert_not_contains "sync-type = git" "$out"

########################################
# Networking
########################################

test_begin "pipeline: systemd+networkd+DHCP writes network config"
reset_chroot_state
SYSTEMD=true
SYSTEMD_NETWORKD=true
SYSTEMD_NETWORKD_DHCP=true
SYSTEMD_NETWORKD_INTERFACE_NAME="en*"
run_pipeline
_netconf="$(command cat "$_PIPELINE_ETCDIR/systemd/network/20-wired.network" 2>/dev/null || true)"
assert_contains "DHCP=yes" "$_netconf"

test_begin "pipeline: systemd+networkd+static writes address config"
reset_chroot_state
SYSTEMD=true
SYSTEMD_NETWORKD=true
SYSTEMD_NETWORKD_DHCP=false
SYSTEMD_NETWORKD_ADDRESSES=("192.168.1.100/24")
SYSTEMD_NETWORKD_GATEWAY="192.168.1.1"
SYSTEMD_NETWORKD_INTERFACE_NAME="eth0"
run_pipeline
_netconf="$(command cat "$_PIPELINE_ETCDIR/systemd/network/20-wired.network" 2>/dev/null || true)"
assert_contains "Address=192.168.1.100/24" "$_netconf"
assert_contains "Gateway=192.168.1.1" "$_netconf"

test_begin "pipeline: OpenRC installs dhcpcd"
reset_chroot_state
SYSTEMD=false
STAGE3_BASENAME="stage3-amd64-openrc"
SYSTEMD_NETWORKD=false
run_pipeline
assert_contains "net-misc/dhcpcd" "$out"

########################################
# Optional features
########################################

test_begin "pipeline: ENABLE_GURU=true enables guru overlay"
reset_chroot_state
ENABLE_GURU=true
run_pipeline
assert_contains "STUB:eselect repository enable guru" "$out"

test_begin "pipeline: ENABLE_GURU=false skips guru"
reset_chroot_state
ENABLE_GURU=false
run_pipeline
assert_not_contains "repository enable guru" "$out"

test_begin "pipeline: ENABLE_SSHD=true calls enable_sshd"
reset_chroot_state
ENABLE_SSHD=true
run_pipeline
assert_call_log_contains "enable_sshd"

test_begin "pipeline: ENABLE_SSHD=false skips enable_sshd"
reset_chroot_state
ENABLE_SSHD=false
run_pipeline
assert_call_log_not_contains "enable_sshd"

test_begin "pipeline: ENABLE_CHRONYD=true calls enable_chronyd"
reset_chroot_state
ENABLE_CHRONYD=true
run_pipeline
assert_call_log_contains "enable_chronyd"

test_begin "pipeline: ENABLE_CHRONYD=false skips enable_chronyd"
reset_chroot_state
ENABLE_CHRONYD=false
run_pipeline
assert_call_log_not_contains "enable_chronyd"

test_begin "pipeline: ENABLE_CRON=true calls enable_cron"
reset_chroot_state
ENABLE_CRON=true
run_pipeline
assert_call_log_contains "enable_cron"

test_begin "pipeline: ENABLE_CRON=false skips enable_cron"
reset_chroot_state
ENABLE_CRON=false
run_pipeline
assert_call_log_not_contains "enable_cron"

test_begin "pipeline: ENABLE_SYSLOGGER=true + OpenRC calls enable_syslogger"
reset_chroot_state
SYSTEMD=false
ENABLE_SYSLOGGER=true
run_pipeline
assert_call_log_contains "enable_syslogger"

test_begin "pipeline: ENABLE_SYSLOGGER=false skips enable_syslogger"
reset_chroot_state
SYSTEMD=false
ENABLE_SYSLOGGER=false
run_pipeline
assert_call_log_not_contains "enable_syslogger"

test_begin "pipeline: ENABLE_SYSLOGGER=true + systemd skips enable_syslogger"
reset_chroot_state
SYSTEMD=true
ENABLE_SYSLOGGER=true
run_pipeline
assert_call_log_not_contains "enable_syslogger"

test_begin "pipeline: ADDITIONAL_PACKAGES installs extra packages"
reset_chroot_state
ADDITIONAL_PACKAGES=("app-editors/vim" "app-misc/tmux")
run_pipeline
assert_contains "app-editors/vim" "$out"
assert_contains "app-misc/tmux" "$out"

test_begin "pipeline: empty ADDITIONAL_PACKAGES skips extra emerge"
reset_chroot_state
ADDITIONAL_PACKAGES=()
run_pipeline
assert_not_contains "Installing additional packages" "$out"

test_begin "pipeline: USE_PORTAGE_TESTING=true adds ACCEPT_KEYWORDS"
reset_chroot_state
USE_PORTAGE_TESTING=true
GENTOO_ARCH="amd64"
run_pipeline
_makeconf="$(command cat "$_PIPELINE_ETCDIR/portage/make.conf" 2>/dev/null || true)"
assert_contains "ACCEPT_KEYWORDS" "$_makeconf"
assert_contains "~amd64" "$_makeconf"

test_begin "pipeline: USE_PORTAGE_TESTING=false skips ACCEPT_KEYWORDS"
reset_chroot_state
USE_PORTAGE_TESTING=false
# Clear make.conf to test that nothing is appended
: > "$_PIPELINE_ETCDIR/portage/make.conf"
run_pipeline
_makeconf="$(command cat "$_PIPELINE_ETCDIR/portage/make.conf" 2>/dev/null || true)"
assert_not_contains "ACCEPT_KEYWORDS" "$_makeconf"

test_begin "pipeline: generates ssh host keys"
reset_chroot_state
run_pipeline
assert_contains "STUB:ssh-keygen -A" "$out"

test_begin "pipeline: installs git"
reset_chroot_state
run_pipeline
assert_contains "dev-vcs/git" "$out"

test_begin "pipeline: enables dracut USE flag on installkernel"
reset_chroot_state
run_pipeline
_installkernel="$(command cat "$_PIPELINE_ETCDIR/portage/package.use/installkernel" 2>/dev/null || true)"
assert_contains "sys-kernel/installkernel dracut" "$_installkernel"

test_begin "pipeline: rejects extra arguments"
reset_chroot_state
run_pipeline  # first run pipeline to set up state
capture_output out rc main_install_gentoo_in_chroot "extra_arg"
assert_neq 0 "$rc"
assert_contains "Too many arguments" "$out"

# Cleanup
command rm -rf "$_PIPELINE_ETCDIR"

test_summary
