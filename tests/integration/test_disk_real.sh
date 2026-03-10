#!/bin/bash
# Integration tests: real disk operations on dd-created loop devices.
# These tests exercise the ACTUAL partitioning and formatting code paths
# (sgdisk, mkfs.*, wipefs, etc.) on loop-backed image files.
#
# Requirements:
#   - pkexec (polkit) for privilege escalation (prompted once)
#   - sgdisk, wipefs, partprobe, mkfs.fat, mkfs.ext4, uuidgen
#   - Optional: mkfs.btrfs, bcachefs, mdadm, cryptsetup
#
# Usage:
#   bash tests/integration/test_disk_real.sh
#
# The script re-execs itself as root via pkexec (single auth prompt),
# creates temporary image files, attaches them as loop devices, runs real
# disk operations, verifies results, then cleans up.
# NO real disks are ever touched.

set -uo pipefail

# ── Self-elevate to root via pkexec (single prompt) ──
if [[ "$(id -u)" -ne 0 ]]; then
	SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
	exec pkexec bash "$SCRIPT_PATH" "$@"
fi

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INTEGRATION_DIR/../unit/test_harness.sh"

PROJECT_DIR="$(dirname "$(dirname "$INTEGRATION_DIR")")"

# ── Check prerequisites ──
function check_prereqs() {
	local missing=()
	for cmd in losetup sgdisk wipefs partprobe mkfs.fat mkfs.ext4 blkid lsblk dd uuidgen; do
		command -v "$cmd" &>/dev/null || missing+=("$cmd")
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "SKIP: Missing required tools: ${missing[*]}" >&2
		exit 0
	fi
}

# ── Image / loop device management ──
CLEANUP_LOOPS=()
CLEANUP_FILES=()
CLEANUP_MOUNTS=()
CLEANUP_MD=()
CLEANUP_LUKS=()
CLEANUP_DIRS=()

function create_test_image() {
	local size_mb="${1:-2048}"
	local img
	img="$(mktemp /tmp/gentoo-test-disk-XXXXXX.img)"
	# Use sparse file: takes no real disk space until written
	dd if=/dev/zero of="$img" bs=1M count=0 seek="$size_mb" status=none 2>/dev/null
	CLEANUP_FILES+=("$img")
	echo "$img"
}

function attach_loop() {
	local img="$1"
	local loop
	loop="$(losetup --find --show --partscan "$img" 2>/dev/null)" \
		|| { echo "FAIL: could not attach loop device for $img" >&2; return 1; }
	CLEANUP_LOOPS+=("$loop")
	echo "$loop"
}

function wait_for_partitions() {
	local loop="$1"
	partprobe "$loop" 2>/dev/null || true
	udevadm settle --timeout=5 2>/dev/null || sleep 2
}

function cleanup() {
	set +e
	for mnt in "${CLEANUP_MOUNTS[@]}"; do
		umount "$mnt" 2>/dev/null
	done
	for md in "${CLEANUP_MD[@]}"; do
		mdadm --stop "$md" 2>/dev/null
	done
	for name in "${CLEANUP_LUKS[@]}"; do
		cryptsetup close "$name" 2>/dev/null
	done
	for loop in "${CLEANUP_LOOPS[@]}"; do
		losetup -d "$loop" 2>/dev/null
	done
	for f in "${CLEANUP_FILES[@]}"; do
		rm -f "$f" 2>/dev/null
	done
	for d in "${CLEANUP_DIRS[@]}"; do
		rm -rf "$d" 2>/dev/null
	done
}
trap cleanup EXIT

# ── Source project scripts ──
export GENTOO_INSTALL_REPO_DIR="$PROJECT_DIR"
export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
export GENTOO_INSTALL_REPO_SCRIPT_PID=$$

source "$PROJECT_DIR/scripts/utils.sh"
source "$PROJECT_DIR/scripts/config.sh"
source "$PROJECT_DIR/scripts/functions.sh"
source "$PROJECT_DIR/scripts/main.sh"

# Override die to not kill test runner
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

# Override interactive/network functions (NOT disk commands)
function ask()        { return 0; }
function flush_stdin() { :; }
function wget()       { echo "STUB:wget $*"; }
function countdown()  { :; }
function emerge()     { echo "STUB:emerge $*"; }
function passwd()     { echo "STUB:passwd $*"; }
function chroot()     { echo "STUB:chroot $*"; }

# UUID_STORAGE_DIR uses real uuidgen — give it a temp dir
UUID_STORAGE_DIR="$(mktemp -d /tmp/gentoo-test-uuids-XXXXXX)"
CLEANUP_DIRS+=("$UUID_STORAGE_DIR")

# Keep TMP_DIR pointed at a safe temp location
TMP_DIR="$(mktemp -d /tmp/gentoo-test-tmp-XXXXXX)"
CLEANUP_DIRS+=("$TMP_DIR")
ROOT_MOUNTPOINT="$TMP_DIR/root"
LUKS_HEADER_BACKUP_DIR="$TMP_DIR/luks-headers"

# ── Reset state helper ──
function reset_disk_state() {
	# Fresh UUID storage per test
	rm -rf "$UUID_STORAGE_DIR"/*
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
	# Clear lsblk cache
	unset CACHED_LSBLK_OUTPUT
}

########################################
# TESTS
########################################

check_prereqs

echo "Running as root (uid=$(id -u)) — all disk commands execute directly."
echo ""

########################################
# Test 1: GPT creation on loop device
########################################

test_begin "real: create GPT partition table on loop device"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	apply_disk_actions 2>/dev/null
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	rc=$?
	assert_eq 0 "$rc" "sgdisk -p should succeed on GPT disk"
	assert_contains "Disk $loop" "$gpt_info"
else
	test_fail "could not create loop device"
fi

########################################
# Test 2: GPT + EFI + root partitions
########################################

test_begin "real: create GPT with EFI and root partitions"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	create_partition new_id="part_efi" id="gpt" size="32MiB" type="efi"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_EFI="part_efi"
	DISK_ID_ROOT="part_root"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 2 "$part_count" "should have 2 partitions"
	assert_contains "EF00" "$gpt_info"
	assert_contains "8300" "$gpt_info"
else
	test_fail "could not create loop device"
fi

########################################
# Test 3: GPT + EFI + swap + root
########################################

test_begin "real: create GPT with EFI, swap, and root partitions"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	create_partition new_id="part_efi" id="gpt" size="16MiB" type="efi"
	create_partition new_id="part_swap" id="gpt" size="16MiB" type="swap"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_EFI="part_efi"
	DISK_ID_SWAP="part_swap"
	DISK_ID_ROOT="part_root"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 3 "$part_count" "should have 3 partitions"
	assert_contains "EF00" "$gpt_info"
	assert_contains "8200" "$gpt_info"
	assert_contains "8300" "$gpt_info"
else
	test_fail "could not create loop device"
fi

########################################
# Test 4: Full classic layout with format (EFI + ext4)
########################################

test_begin "real: classic layout EFI + ext4 with formatting"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_classic_single_disk_layout swap=false root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 2 "$part_count" "should have 2 partitions (efi + root)"
	# Verify EFI is FAT32
	efi_part="${loop}p1"
	[[ -e "$efi_part" ]] || efi_part="${loop}1"
	if [[ -e "$efi_part" ]]; then
		fs_type="$(blkid -s TYPE -o value "$efi_part" 2>/dev/null)" || fs_type=""
		assert_eq "vfat" "$fs_type" "EFI partition should be FAT32"
	fi
	# Verify root is ext4
	root_part="${loop}p2"
	[[ -e "$root_part" ]] || root_part="${loop}2"
	if [[ -e "$root_part" ]]; then
		fs_type="$(blkid -s TYPE -o value "$root_part" 2>/dev/null)" || fs_type=""
		assert_eq "ext4" "$fs_type" "root partition should be ext4"
	fi
else
	test_fail "could not create loop device"
fi

########################################
# Test 5: Classic layout with swap
########################################

test_begin "real: classic layout EFI + swap + ext4"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_classic_single_disk_layout swap=16MiB root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 3 "$part_count" "should have 3 partitions (efi + swap + root)"
	swap_part="${loop}p2"
	[[ -e "$swap_part" ]] || swap_part="${loop}2"
	if [[ -e "$swap_part" ]]; then
		fs_type="$(blkid -s TYPE -o value "$swap_part" 2>/dev/null)" || fs_type=""
		assert_eq "swap" "$fs_type" "swap partition should be swap"
	fi
else
	test_fail "could not create loop device"
fi

########################################
# Test 6: Classic layout with btrfs (if available)
########################################

if command -v mkfs.btrfs &>/dev/null; then
	test_begin "real: classic layout EFI + btrfs"
	img="$(create_test_image 2048)"
	loop="$(attach_loop "$img")"
	if [[ -n "$loop" ]]; then
		reset_disk_state
		create_classic_single_disk_layout swap=false root_fs=btrfs "$loop"
		apply_disk_actions 2>/dev/null
		wait_for_partitions "$loop"
		root_part="${loop}p2"
		[[ -e "$root_part" ]] || root_part="${loop}2"
		if [[ -e "$root_part" ]]; then
			fs_type="$(blkid -s TYPE -o value "$root_part" 2>/dev/null)" || fs_type=""
			assert_eq "btrfs" "$fs_type" "root partition should be btrfs"
		fi
	else
		test_fail "could not create loop device"
	fi
else
	echo "  SKIP  real: classic layout EFI + btrfs (mkfs.btrfs not available)"
fi

########################################
# Test 7: BIOS boot type
########################################

test_begin "real: classic layout BIOS + ext4"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_classic_single_disk_layout swap=false type=bios root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 2 "$part_count" "should have 2 partitions (bios + root)"
	assert_contains "EF02" "$gpt_info"
	assert_contains "8300" "$gpt_info"
else
	test_fail "could not create loop device"
fi

########################################
# Test 8: LUKS encryption (if cryptsetup available)
########################################

if command -v cryptsetup &>/dev/null; then
	test_begin "real: classic layout with LUKS encryption"
	img="$(create_test_image 2048)"
	loop="$(attach_loop "$img")"
	if [[ -n "$loop" ]]; then
		reset_disk_state
		GENTOO_INSTALL_ENCRYPTION_KEY="test-password-12345"
		create_classic_single_disk_layout swap=false luks=true root_fs=ext4 "$loop"
		apply_disk_actions 2>/dev/null
		wait_for_partitions "$loop"
		# Verify LUKS exists on root partition
		root_part="${loop}p2"
		[[ -e "$root_part" ]] || root_part="${loop}2"
		if [[ -e "$root_part" ]]; then
			cryptsetup isLuks "$root_part" 2>/dev/null; luks_rc=$?
			assert_eq 0 "$luks_rc" "root partition should be LUKS"
			CLEANUP_LUKS+=("root")
		fi
	else
		test_fail "could not create loop device"
	fi
else
	echo "  SKIP  real: classic layout with LUKS encryption (cryptsetup not available)"
fi

########################################
# Test 9: Verify partuuids match
########################################

test_begin "real: partition UUIDs match configured values"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	create_partition new_id="part_efi" id="gpt" size="32MiB" type="efi"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_EFI="part_efi"
	DISK_ID_ROOT="part_root"
	expected_efi_uuid="${DISK_ID_TO_UUID[part_efi]}"
	expected_root_uuid="${DISK_ID_TO_UUID[part_root]}"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	efi_part="${loop}p1"
	[[ -e "$efi_part" ]] || efi_part="${loop}1"
	root_part="${loop}p2"
	[[ -e "$root_part" ]] || root_part="${loop}2"
	if [[ -e "$efi_part" && -e "$root_part" ]]; then
		actual_efi_uuid="$(blkid -s PARTUUID -o value "$efi_part" 2>/dev/null)" || actual_efi_uuid=""
		actual_root_uuid="$(blkid -s PARTUUID -o value "$root_part" 2>/dev/null)" || actual_root_uuid=""
		assert_eq "${expected_efi_uuid,,}" "${actual_efi_uuid,,}" "EFI partition UUID should match"
		assert_eq "${expected_root_uuid,,}" "${actual_root_uuid,,}" "root partition UUID should match"
	else
		test_fail "partitions did not appear"
	fi
else
	test_fail "could not create loop device"
fi

########################################
# Test 10: Mount formatted partitions
########################################

test_begin "real: mount formatted ext4 root partition"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_classic_single_disk_layout swap=false root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	root_part="${loop}p2"
	[[ -e "$root_part" ]] || root_part="${loop}2"
	if [[ -e "$root_part" ]]; then
		mnt="$(mktemp -d /tmp/gentoo-test-mount-XXXXXX)"
		CLEANUP_MOUNTS+=("$mnt")
		mount "$root_part" "$mnt" 2>/dev/null; mount_rc=$?
		assert_eq 0 "$mount_rc" "should be able to mount ext4 root"
		if [[ $mount_rc -eq 0 ]]; then
			echo 'hello gentoo' > "$mnt/test.txt"
			content="$(cat "$mnt/test.txt" 2>/dev/null)" || content=""
			assert_eq "hello gentoo" "$content" "should read back written data"
			umount "$mnt" 2>/dev/null
		fi
	else
		test_fail "root partition did not appear"
	fi
else
	test_fail "could not create loop device"
fi

########################################
# Test 11: Multiple GPT re-creation (idempotency)
########################################

test_begin "real: re-create GPT on same device"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	# First pass
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	create_partition new_id="part_efi" id="gpt" size="32MiB" type="efi"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_EFI="part_efi"
	DISK_ID_ROOT="part_root"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	# Second pass — overwrite with new layout
	reset_disk_state
	create_gpt new_id="gpt2" device="$loop"
	create_partition new_id="part_only" id="gpt2" size="remaining" type="linux"
	DISK_ID_ROOT="part_only"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 1 "$part_count" "second pass should have 1 partition"
else
	test_fail "could not create loop device"
fi

########################################
# Test 12: Verify filesystem labels
########################################

test_begin "real: filesystem labels are set correctly"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_classic_single_disk_layout swap=16MiB root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	efi_part="${loop}p1"
	[[ -e "$efi_part" ]] || efi_part="${loop}1"
	if [[ -e "$efi_part" ]]; then
		label="$(blkid -s LABEL -o value "$efi_part" 2>/dev/null)" || label=""
		assert_eq "efi" "$label" "EFI partition label"
	fi
	swap_part="${loop}p2"
	[[ -e "$swap_part" ]] || swap_part="${loop}2"
	if [[ -e "$swap_part" ]]; then
		label="$(blkid -s LABEL -o value "$swap_part" 2>/dev/null)" || label=""
		assert_eq "swap" "$label" "swap partition label"
	fi
	root_part="${loop}p3"
	[[ -e "$root_part" ]] || root_part="${loop}3"
	if [[ -e "$root_part" ]]; then
		label="$(blkid -s LABEL -o value "$root_part" 2>/dev/null)" || label=""
		assert_eq "root" "$label" "root partition label"
	fi
else
	test_fail "could not create loop device"
fi

########################################
# Test 13: Existing partitions layout
########################################

test_begin "real: existing partitions layout preserves disk"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	reset_disk_state
	create_gpt new_id="gpt" device="$loop"
	create_partition new_id="part_efi" id="gpt" size="32MiB" type="efi"
	create_partition new_id="part_root" id="gpt" size="remaining" type="linux"
	DISK_ID_EFI="part_efi"
	DISK_ID_ROOT="part_root"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	efi_part="${loop}p1"
	[[ -e "$efi_part" ]] || efi_part="${loop}1"
	root_part="${loop}p2"
	[[ -e "$root_part" ]] || root_part="${loop}2"
	reset_disk_state
	create_existing_partitions_layout swap=false boot="$efi_part" "$root_part"
	assert_eq true "$NO_PARTITIONING_OR_FORMATTING"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 2 "$part_count" "original partitions should remain"
else
	test_fail "could not create loop device"
fi

########################################
# Test 14: wipefs clears signatures on re-partition
########################################

test_begin "real: wipefs clears signatures before re-partitioning"
img="$(create_test_image 2048)"
loop="$(attach_loop "$img")"
if [[ -n "$loop" ]]; then
	# Create and format first
	reset_disk_state
	create_classic_single_disk_layout swap=false root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	# Re-create with different layout
	reset_disk_state
	create_classic_single_disk_layout swap=16MiB root_fs=ext4 "$loop"
	apply_disk_actions 2>/dev/null
	wait_for_partitions "$loop"
	gpt_info="$(sgdisk -p "$loop" 2>&1)"
	part_count="$(echo "$gpt_info" | grep -cE '^\s+[0-9]+')" || part_count=0
	assert_eq 3 "$part_count" "re-partitioned disk should have 3 partitions"
else
	test_fail "could not create loop device"
fi

########################################
# Test 15: RAID0+LUKS config (if mdadm available)
########################################

if command -v mdadm &>/dev/null; then
	test_begin "real: RAID0+LUKS layout configures correctly for 2 disks"
	img1="$(create_test_image 2048)"
	img2="$(create_test_image 2048)"
	loop1="$(attach_loop "$img1")"
	loop2="$(attach_loop "$img2")"
	if [[ -n "$loop1" && -n "$loop2" ]]; then
		reset_disk_state
		HOSTNAME="testhost"
		create_raid0_luks_layout swap=false root_fs=ext4 "$loop1" "$loop2"
		assert_contains "action=create_gpt" "${DISK_ACTIONS[*]}"
		assert_contains "action=create_raid" "${DISK_ACTIONS[*]}"
		assert_contains "action=create_luks" "${DISK_ACTIONS[*]}"
		assert_eq true "$USED_RAID"
		assert_eq true "$USED_LUKS"
	else
		test_fail "could not create loop devices"
	fi
else
	echo "  SKIP  real: RAID0+LUKS layout (mdadm not available)"
fi

test_summary
