#!/bin/bash
# Test environment: sources project scripts with safe overrides.
# Source this after test_harness.sh to get all functions available for testing.
# This NEVER touches real disks — all dangerous functions are stubbed.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$TEST_DIR")")"

# Set required environment for protection.sh
export GENTOO_INSTALL_REPO_DIR="$PROJECT_DIR"
export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
export GENTOO_INSTALL_REPO_SCRIPT_PID=$$

# Source the scripts
source "$PROJECT_DIR/scripts/utils.sh"
source "$PROJECT_DIR/scripts/config.sh"
source "$PROJECT_DIR/scripts/functions.sh"
source "$PROJECT_DIR/scripts/main.sh"

# ── Stub out dangerous / system-dependent functions ──

# Filesystem/device operations
function sgdisk()     { echo "STUB:sgdisk $*"; }
function wipefs()     { echo "STUB:wipefs $*"; }
function partprobe()  { echo "STUB:partprobe $*"; }
function mkfs.fat()   { echo "STUB:mkfs.fat $*"; }
function mkfs.ext4()  { echo "STUB:mkfs.ext4 $*"; }
function mkfs.btrfs() { echo "STUB:mkfs.btrfs $*"; }
function mkswap()     { echo "STUB:mkswap $*"; }
function mount()      { echo "STUB:mount $*"; }
function umount()     { echo "STUB:umount $*"; }
function mountpoint()  { return 1; }
function cryptsetup() { echo "STUB:cryptsetup $*"; }
function mdadm()      { echo "STUB:mdadm $*"; }
function zpool()      { echo "STUB:zpool $*"; }
function zfs()        { echo "STUB:zfs $*"; }
function bcachefs()   { echo "STUB:bcachefs $*"; }
function swapon()     { echo "STUB:swapon $*"; }
function swapoff()    { echo "STUB:swapoff $*"; }
function lsblk()      { echo "STUB:lsblk"; }
function blkid()      { echo "STUB:blkid $*"; }
function efibootmgr() { echo "STUB:efibootmgr $*"; }

# Network / download
function wget()       { echo "STUB:wget $*"; }

# Interactive functions
function ask()        { return 0; }
function flush_stdin() { :; }

# System commands that shouldn't run in tests
function emerge()     { echo "STUB:emerge $*"; }
function passwd()     { echo "STUB:passwd $*"; }
function chroot()     { echo "STUB:chroot $*"; }

# Override load_or_generate_uuid to be deterministic
_UUID_COUNTER=0
function load_or_generate_uuid() {
	_UUID_COUNTER=$((_UUID_COUNTER + 1))
	printf "00000000-0000-0000-0000-%012d" "$_UUID_COUNTER"
}

# Override die to not kill the test runner
function die() {
	echo "DIE: $*" >&2
	return 1
}

function die_trace() {
	local idx="${1:-0}"
	shift
	echo "DIE_TRACE: $*" >&2
	return 1
}

# ── Helper to reset global state between tests ──
function reset_disk_state() {
	_UUID_COUNTER=0
	DISK_ACTIONS=()
	DISK_DRACUT_CMDLINE=()
	unset DISK_ID_TO_RESOLVABLE; declare -gA DISK_ID_TO_RESOLVABLE
	unset DISK_ID_PART_TO_GPT_ID; declare -gA DISK_ID_PART_TO_GPT_ID
	unset DISK_ID_TO_UUID; declare -gA DISK_ID_TO_UUID
	unset DISK_GPT_HAD_SIZE_REMAINING; declare -gA DISK_GPT_HAD_SIZE_REMAINING
	USED_RAID=false
	USED_LUKS=false
	USED_ZFS=false
	USED_BTRFS=false
	USED_BCACHEFS=false
	USED_ENCRYPTION=false
	NO_PARTITIONING_OR_FORMATTING=false
	IS_EFI=false
	unset DISK_ID_EFI DISK_ID_BIOS DISK_ID_SWAP DISK_ID_ROOT
	unset DISK_ID_ROOT_TYPE DISK_ID_ROOT_MOUNT_OPTS
	unset BCACHEFS_DEVICE_IDS
}
