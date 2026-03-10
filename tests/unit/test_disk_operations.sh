#!/bin/bash
# Tests for disk_* action functions in EXECUTION mode (non-summary)
# Tests verify correct command construction via stubs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

# Ensure we're in execution mode, not summary mode
unset disk_action_summarize_only

# Use predictable device resolution
setup_device_resolution

########################################
# disk_create_gpt
########################################

test_begin "disk_create_gpt exec: with device= argument"
reset_disk_state
create_gpt new_id="gpt1" device="/dev/sda"
capture_output out rc apply_disk_action "action=create_gpt" "new_id=gpt1" "device=/dev/sda"
assert_eq 0 "$rc"
assert_contains "STUB:wipefs" "$out"
assert_contains "/dev/sda" "$out"
assert_contains "Creating new gpt partition table" "$out"
assert_contains "STUB:partprobe" "$out"

test_begin "disk_create_gpt exec: with id= argument"
reset_disk_state
register_existing new_id="base" device="/dev/sdb"
create_gpt new_id="gpt2" id="base"
capture_output out rc apply_disk_action "action=create_gpt" "new_id=gpt2" "id=base"
assert_eq 0 "$rc"
assert_contains "STUB:wipefs" "$out"
# Note: sgdisk output goes to /dev/null so we check einfo instead
assert_contains "Creating new gpt partition table (gpt2)" "$out"

test_begin "disk_create_gpt exec: wipefs failure propagates"
reset_disk_state
function wipefs() { echo "STUB:wipefs $*" >&2; return 1; }
create_gpt new_id="gptfail" device="/dev/sda"
capture_output out rc apply_disk_action "action=create_gpt" "new_id=gptfail" "device=/dev/sda"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
assert_contains "erase previous file system" "$out"
function wipefs() { echo "STUB:wipefs $*"; }

test_begin "disk_create_gpt exec: sgdisk failure propagates"
reset_disk_state
function sgdisk() { return 1; }
create_gpt new_id="gptfail2" device="/dev/sda"
capture_output out rc apply_disk_action "action=create_gpt" "new_id=gptfail2" "device=/dev/sda"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function sgdisk() { echo "STUB:sgdisk $*"; }

########################################
# disk_create_partition
########################################

test_begin "disk_create_partition exec: type bios maps to ef02"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_bios" id="gpt" size="1MiB" type="bios"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_bios" "id=gpt" "size=1MiB" "type=bios"
assert_eq 0 "$rc"
assert_contains "type=ef02" "$out"

test_begin "disk_create_partition exec: type efi maps to ef00"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_efi" id="gpt" size="512MiB" type="efi"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_efi" "id=gpt" "size=512MiB" "type=efi"
assert_eq 0 "$rc"
assert_contains "type=ef00" "$out"

test_begin "disk_create_partition exec: type swap maps to 8200"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_swap" id="gpt" size="4GiB" type="swap"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_swap" "id=gpt" "size=4GiB" "type=swap"
assert_eq 0 "$rc"
assert_contains "type=8200" "$out"

test_begin "disk_create_partition exec: type raid maps to fd00"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_raid" id="gpt" size="10GiB" type="raid"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_raid" "id=gpt" "size=10GiB" "type=raid"
assert_eq 0 "$rc"
assert_contains "type=fd00" "$out"

test_begin "disk_create_partition exec: type luks maps to 8309"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_luks" id="gpt" size="10GiB" type="luks"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_luks" "id=gpt" "size=10GiB" "type=luks"
assert_eq 0 "$rc"
assert_contains "type=8309" "$out"

test_begin "disk_create_partition exec: type linux maps to 8300"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_linux" id="gpt" size="remaining" type="linux"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_linux" "id=gpt" "size=remaining" "type=linux"
assert_eq 0 "$rc"
assert_contains "type=8300" "$out"

test_begin "disk_create_partition exec: size=remaining in einfo"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_rem" id="gpt" size="remaining" type="linux"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_rem" "id=gpt" "size=remaining" "type=linux"
assert_eq 0 "$rc"
assert_contains "size=remaining" "$out"

test_begin "disk_create_partition exec: custom hex type passes through"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_custom" id="gpt" size="1GiB" type="8e00"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_custom" "id=gpt" "size=1GiB" "type=8e00"
assert_eq 0 "$rc"
assert_contains "type=8e00" "$out"

test_begin "disk_create_partition exec: sgdisk failure dies"
reset_disk_state
function sgdisk() { return 1; }
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p_fail" id="gpt" size="1GiB" type="linux"
capture_output out rc apply_disk_action "action=create_partition" "new_id=p_fail" "id=gpt" "size=1GiB" "type=linux"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function sgdisk() { echo "STUB:sgdisk $*"; }

########################################
# disk_create_raid
########################################

test_begin "disk_create_raid exec: level=1 name=efi uses metadata=1.0"
reset_disk_state
HOSTNAME="testhost"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="r1" id="g1" size="512MiB" type="raid"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="r2" id="g2" size="512MiB" type="raid"
create_raid new_id="md_efi" level=1 name="efi" ids="r1;r2"
capture_output out rc apply_disk_action "action=create_raid" "new_id=md_efi" "level=1" "name=efi" "ids=r1;r2"
assert_eq 0 "$rc"
assert_contains "--metadata=1.0" "$out"

test_begin "disk_create_raid exec: level=1 name=root uses metadata=1.2"
reset_disk_state
HOSTNAME="testhost"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="r1" id="g1" size="10GiB" type="raid"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="r2" id="g2" size="10GiB" type="raid"
create_raid new_id="md_root" level=1 name="root" ids="r1;r2"
capture_output out rc apply_disk_action "action=create_raid" "new_id=md_root" "level=1" "name=root" "ids=r1;r2"
assert_eq 0 "$rc"
assert_contains "--metadata=1.2" "$out"

test_begin "disk_create_raid exec: verifies mdadm args"
reset_disk_state
HOSTNAME="myhost"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="r1" id="g1" size="10GiB" type="raid"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="r2" id="g2" size="10GiB" type="raid"
create_raid new_id="mdargs" level=1 name="root" ids="r1;r2"
capture_output out rc apply_disk_action "action=create_raid" "new_id=mdargs" "level=1" "name=root" "ids=r1;r2"
assert_contains "--create" "$out"
assert_contains "--level=1" "$out"
assert_contains "--raid-devices=2" "$out"
assert_contains "--homehost=myhost" "$out"
assert_contains "/dev/md/root" "$out"

test_begin "disk_create_raid exec: resolves multiple member devices"
reset_disk_state
HOSTNAME="testhost"
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="m1" id="g1" size="10GiB" type="raid"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="m2" id="g2" size="10GiB" type="raid"
create_raid new_id="md_multi" level=1 name="root" ids="m1;m2"
capture_output out rc apply_disk_action "action=create_raid" "new_id=md_multi" "level=1" "name=root" "ids=m1;m2"
assert_contains "$_FAKE_DEV_DIR/m1" "$out"
assert_contains "$_FAKE_DEV_DIR/m2" "$out"

test_begin "disk_create_raid exec: mdadm failure dies"
reset_disk_state
HOSTNAME="testhost"
function mdadm() { return 1; }
create_gpt new_id="g1" device="/dev/sda"
create_partition new_id="r1" id="g1" size="10GiB" type="raid"
create_gpt new_id="g2" device="/dev/sdb"
create_partition new_id="r2" id="g2" size="10GiB" type="raid"
create_raid new_id="mdfail" level=1 name="root" ids="r1;r2"
capture_output out rc apply_disk_action "action=create_raid" "new_id=mdfail" "level=1" "name=root" "ids=r1;r2"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function mdadm() { echo "STUB:mdadm $*"; }

########################################
# disk_create_luks
########################################

test_begin "disk_create_luks exec: with id= argument"
reset_disk_state
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="luks"
create_luks new_id="crypt" name="cryptroot" id="p1"
capture_output out rc apply_disk_action "action=create_luks" "new_id=crypt" "name=cryptroot" "id=p1"
assert_eq 0 "$rc"
assert_contains "STUB:cryptsetup luksFormat" "$out"
assert_contains "--type luks2" "$out"
assert_contains "--cipher aes-xts-plain64" "$out"
assert_contains "--hash sha512" "$out"
assert_contains "--pbkdf argon2id" "$out"
assert_contains "--key-size 512" "$out"

test_begin "disk_create_luks exec: with device= argument"
reset_disk_state
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
create_luks new_id="crypt2" name="cryptdev" device="/dev/sdb"
capture_output out rc apply_disk_action "action=create_luks" "new_id=crypt2" "name=cryptdev" "device=/dev/sdb"
assert_eq 0 "$rc"
assert_contains "/dev/sdb" "$out"
assert_contains "STUB:cryptsetup luksFormat" "$out"

test_begin "disk_create_luks exec: header backup is created"
reset_disk_state
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="luks"
create_luks new_id="cryptbk" name="cryptroot" id="p1"
capture_output out rc apply_disk_action "action=create_luks" "new_id=cryptbk" "name=cryptroot" "id=p1"
assert_contains "STUB:cryptsetup luksHeaderBackup" "$out"

test_begin "disk_create_luks exec: cryptsetup open is called"
reset_disk_state
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="luks"
create_luks new_id="cryptop" name="cryptroot" id="p1"
capture_output out rc apply_disk_action "action=create_luks" "new_id=cryptop" "name=cryptroot" "id=p1"
assert_contains "STUB:cryptsetup open" "$out"
assert_contains "cryptroot" "$out"

test_begin "disk_create_luks exec: luksFormat failure dies"
reset_disk_state
export GENTOO_INSTALL_ENCRYPTION_KEY="testkey12345"
LUKS_HEADER_BACKUP_DIR="/tmp/gentoo-test/luks-headers"
function cryptsetup() { return 1; }
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="luks"
create_luks new_id="cryptfail" name="cryptroot" id="p1"
capture_output out rc apply_disk_action "action=create_luks" "new_id=cryptfail" "name=cryptroot" "id=p1"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function cryptsetup() { echo "STUB:cryptsetup $*"; }

########################################
# disk_create_dummy (execution mode)
########################################

test_begin "disk_create_dummy exec: is a no-op in execution mode"
reset_disk_state
create_dummy new_id="dum" device="/dev/sdc"
capture_output out rc apply_disk_action "action=create_dummy" "new_id=dum" "device=/dev/sdc"
assert_eq 0 "$rc"

########################################
# disk_format: execution mode
########################################

test_begin "disk_format exec: efi with label calls mkfs.fat"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="512MiB" type="efi"
format id="p1" type="efi" label="EFI"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=efi" "label=EFI"
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.fat -F 32 -n EFI" "$out"

test_begin "disk_format exec: efi without label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="512MiB" type="efi"
format id="p1" type="efi"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=efi" "label="
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.fat -F 32" "$out"

test_begin "disk_format exec: bios with label calls mkfs.fat"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="1MiB" type="bios"
format id="p1" type="bios" label="BIOS"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=bios" "label=BIOS"
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.fat -F 32 -n BIOS" "$out"

test_begin "disk_format exec: swap with label calls mkswap"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="4GiB" type="swap"
format id="p1" type="swap" label="swap"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=swap" "label=swap"
assert_eq 0 "$rc"
assert_contains "STUB:mkswap -L swap" "$out"

test_begin "disk_format exec: swap without label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="4GiB" type="swap"
format id="p1" type="swap"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=swap" "label="
assert_eq 0 "$rc"
assert_contains "STUB:mkswap" "$out"

test_begin "disk_format exec: ext4 with label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="ext4" label="root"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=ext4" "label=root"
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.ext4 -q -L root" "$out"

test_begin "disk_format exec: ext4 without label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="ext4"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=ext4" "label="
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.ext4 -q" "$out"

test_begin "disk_format exec: btrfs with label calls mkfs.btrfs"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="btrfs" label="btrfsroot"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=btrfs" "label=btrfsroot"
assert_eq 0 "$rc"
assert_contains "STUB:mkfs.btrfs -q -L btrfsroot" "$out"

test_begin "disk_format exec: btrfs triggers init_btrfs"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="btrfs"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=btrfs" "label="
assert_eq 0 "$rc"
assert_contains "STUB:mount" "$out"
assert_contains "STUB:btrfs subvolume create" "$out"
assert_contains "STUB:btrfs subvolume set-default" "$out"
assert_contains "STUB:umount" "$out"

test_begin "disk_format exec: bcachefs with label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="bcachefs" label="bcroot"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=bcachefs" "label=bcroot"
assert_eq 0 "$rc"
assert_contains "STUB:bcachefs format" "$out"
assert_contains "-L bcroot" "$out"

test_begin "disk_format exec: bcachefs without label"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="bcachefs"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=bcachefs" "label="
assert_eq 0 "$rc"
assert_contains "STUB:bcachefs format" "$out"

test_begin "disk_format exec: unknown type dies"
reset_disk_state
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
# Don't call config builder 'format' with invalid type (it would die_trace at top level)
# Just test apply_disk_action directly
capture_output out rc apply_disk_action "action=format" "id=p1" "type=xfs" "label="
assert_neq 0 "$rc"
assert_contains "Unknown filesystem type" "$out"

test_begin "disk_format exec: wipefs failure dies"
reset_disk_state
function wipefs() { return 1; }
create_gpt new_id="gpt" device="/dev/sda"
create_partition new_id="p1" id="gpt" size="remaining" type="linux"
format id="p1" type="ext4"
capture_output out rc apply_disk_action "action=format" "id=p1" "type=ext4" "label="
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function wipefs() { echo "STUB:wipefs $*"; }

########################################
# init_btrfs
########################################

test_begin "init_btrfs: calls correct sequence"
reset_disk_state
capture_output out rc init_btrfs "/dev/sda1" "test-device"
assert_eq 0 "$rc"
assert_contains "STUB:mount /dev/sda1 /btrfs" "$out"
assert_contains "STUB:btrfs subvolume create /btrfs/root" "$out"
assert_contains "STUB:btrfs subvolume set-default /btrfs/root" "$out"
assert_contains "STUB:umount /btrfs" "$out"

test_begin "init_btrfs: mount failure dies"
reset_disk_state
function mount() { return 1; }
capture_output out rc init_btrfs "/dev/sda1" "test-device"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function mount() { echo "STUB:mount $*"; }

test_begin "init_btrfs: subvolume create failure dies"
reset_disk_state
function btrfs() {
	if [[ "$1" == "subvolume" && "$2" == "create" ]]; then
		return 1
	fi
	echo "STUB:btrfs $*"
}
capture_output out rc init_btrfs "/dev/sda1" "test-device"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function btrfs() { echo "STUB:btrfs $*"; }

test_begin "init_btrfs: umount failure dies"
reset_disk_state
function umount() { return 1; }
capture_output out rc init_btrfs "/dev/sda1" "test-device"
assert_neq 0 "$rc"
assert_contains "DIE" "$out"
function umount() { echo "STUB:umount $*"; }

test_summary
