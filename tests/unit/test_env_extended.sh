#!/bin/bash
# Extended test environment stubs for testing execution-mode paths.
# Source this AFTER test_env.sh to get additional stubs for system commands
# that are called during non-summary disk operations and chroot pipeline.

# ── Additional system command stubs ──

function locale-gen()               { echo "STUB:locale-gen $*"; }
function eselect()                  { echo "STUB:eselect $*"; }
function systemd-machine-id-setup() { echo "STUB:systemd-machine-id-setup $*"; }
function mirrorselect()             { echo "STUB:mirrorselect $*"; }
function ssh-keygen()               { echo "STUB:ssh-keygen $*"; }
function dracut()                   { echo "STUB:dracut $*"; }
function syslinux()                 { echo "STUB:syslinux $*"; }
function dd()                       { echo "STUB:dd $*"; }
function tar()                      { echo "STUB:tar $*"; }
function hwclock()                  { echo "STUB:hwclock $*"; }
function chronyd()                  { echo "STUB:chronyd $*"; }
function date()                     { echo "STUB:date $*"; }
function gpg()                      { echo "STUB:gpg $*"; }
function btrfs()                    { echo "STUB:btrfs $*"; }
function systemctl()                { echo "STUB:systemctl $*"; }
function rc-update()                { echo "STUB:rc-update $*"; }
function emerge-webrsync()          { echo "STUB:emerge-webrsync $*"; }
function env-update()               { echo "STUB:env-update $*"; }
function sleep()                    { :; }

# File operations that need stubbing in execution mode
function readlink()                 { echo "STUB:readlink $*"; }
function realpath()                 { echo "$1"; }
function cp()                       { echo "STUB:cp $*"; }
function git()                      { echo "STUB:git $*"; }
function rm()                       { echo "STUB:rm $*"; }
function chown()                    { echo "STUB:chown $*"; }
function ln()                       { echo "STUB:ln $*"; }

# Override sed: by default just echo stub, but tests can override for specific needs
function sed()                      { echo "STUB:sed $*"; }

# install(1) command stub
function install()                  { echo "STUB:install $*"; }

# System info stubs
function nproc()                    { echo "4"; }
function uname()                    { echo "x86_64"; }
function cpuid2cpuflags()           { echo "CPU_FLAGS_X86: aes avx avx2 sse sse2"; }

# find stub — returns predictable output based on context
function find() {
	if [[ "$*" == *vmlinuz* ]] || [[ "$*" == *kernel* ]]; then
		echo "vmlinuz-6.1.0-gentoo"
	else
		echo "STUB:find $*"
	fi
}

# Override try() to just execute the command (no interactive retry)
function try() { "$@"; }

# ── Device resolution helper for execution-mode tests ──

# Temp dir for fake device files (so -e checks pass)
_FAKE_DEV_DIR="/tmp/_gtest_devs_$$"

function setup_device_resolution() {
	command rm -rf "$_FAKE_DEV_DIR" 2>/dev/null
	command mkdir -p "$_FAKE_DEV_DIR"
	function resolve_device_by_id() {
		local id="$1"
		command touch "$_FAKE_DEV_DIR/${id}"
		echo -n "$_FAKE_DEV_DIR/${id}"
	}
}

# ── Call logging infrastructure (file-based for subshell persistence) ──

_CALL_LOG_FILE="$(command mktemp)"

function log_call() {
	echo "$*" >> "$_CALL_LOG_FILE"
}

function reset_call_log() {
	: > "$_CALL_LOG_FILE"
}

function assert_call_log_contains() {
	local needle="$1"
	local msg="${2:-expected CALL_LOG to contain '$needle'}"
	if command grep -qF "$needle" "$_CALL_LOG_FILE" 2>/dev/null; then
		test_pass
	else
		test_fail "$msg"
	fi
}

function assert_call_log_not_contains() {
	local needle="$1"
	local msg="${2:-expected CALL_LOG NOT to contain '$needle'}"
	if command grep -qF "$needle" "$_CALL_LOG_FILE" 2>/dev/null; then
		test_fail "$msg"
	else
		test_pass
	fi
}

# ── Chroot pipeline state reset ──

function reset_chroot_state() {
	reset_disk_state
	SYSTEMD=true
	MUSL=false
	KEYMAP="us"
	KEYMAP_INITRAMFS="us"
	HOSTNAME="gentoo"
	TIMEZONE="UTC"
	LOCALE="C.UTF-8"
	LOCALES="C.UTF-8 UTF-8"
	PORTAGE_SYNC_TYPE="rsync"
	PORTAGE_GIT_FULL_HISTORY=false
	PORTAGE_GIT_MIRROR=""
	SELECT_MIRRORS=false
	SELECT_MIRRORS_LARGE_FILE=false
	ENABLE_SSHD=false
	ENABLE_CHRONYD=false
	ENABLE_CRON=false
	CRON_TYPE=dcron
	ENABLE_SYSLOGGER=false
	SYSLOGGER_TYPE=sysklogd
	ENABLE_BINPKG=false
	ENABLE_GURU=false
	KERNEL_TYPE="source"
	USE_PORTAGE_TESTING=false
	ADDITIONAL_PACKAGES=()
	ROOT_SSH_AUTHORIZED_KEYS=""
	SYSTEMD_NETWORKD=false
	SYSTEMD_NETWORKD_DHCP=true
	SYSTEMD_NETWORKD_INTERFACE_NAME="en*"
	SYSTEMD_NETWORKD_ADDRESSES=()
	SYSTEMD_NETWORKD_GATEWAY=""
	SYSTEMD_INITRAMFS_SSHD=false
	GENTOO_ARCH="amd64"
	STAGE3_BASENAME="stage3-amd64-systemd"
	STAGE3_VARIANT="systemd"
	ROOT_MOUNTPOINT="/tmp/gentoo-test/root"
	TMP_DIR="/tmp/gentoo-test"
	UUID_STORAGE_DIR="/tmp/gentoo-test/uuids"
	LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
	GENTOO_INSTALL_REPO_BIND="/tmp/gentoo-test/repo"
	GENTOO_INSTALL_REPO_DIR_ORIGINAL="$PROJECT_DIR"
	GENTOO_MIRROR="https://distfiles.gentoo.org"
	IS_EFI=true
	DISK_ID_EFI="efi"
	DISK_ID_ROOT="root"
	DISK_ID_ROOT_TYPE="ext4"
	DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime"
	DISK_DRACUT_CMDLINE=()
	unset DISK_ID_BIOS
	unset DISK_ID_SWAP
	unset EXECUTED_IN_CHROOT
}
