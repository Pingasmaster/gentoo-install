#!/bin/bash
# Tests for configure_base_system and configure_portage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env_extended.sh"

setup_device_resolution

# Override env_update to be a no-op
function env_update() { echo "STUB:env_update"; }

# Override source to avoid trying to source /etc/profile
function source() {
	if [[ "$1" == "/etc/profile" ]]; then
		return 0
	fi
	builtin source "$@"
}

# Override chmod to not fail
function chmod() { echo "STUB:chmod $*"; }

# Override mkdir_or_die and touch_or_die to not require real dirs
function mkdir_or_die() { echo "STUB:mkdir_or_die $*"; }
function touch_or_die() { echo "STUB:touch_or_die $*"; }

# Override awk for /proc/meminfo
function awk() { echo "8"; }

# Create a temp dir that pretends to be /etc/portage
_TEST_ETCDIR="$(command mktemp -d)"

function _setup_etcdir() {
	command rm -rf "$_TEST_ETCDIR"
	_TEST_ETCDIR="$(command mktemp -d)"
	command mkdir -p "$_TEST_ETCDIR/portage/package.use"
	command mkdir -p "$_TEST_ETCDIR/portage/package.keywords"
	command mkdir -p "$_TEST_ETCDIR/portage/gnupg"
	command touch "$_TEST_ETCDIR/portage/package.license"
	command touch "$_TEST_ETCDIR/portage/make.conf"
	command touch "$_TEST_ETCDIR/hostname"
	command touch "$_TEST_ETCDIR/vconsole.conf"
	command touch "$_TEST_ETCDIR/locale.conf"
	command touch "$_TEST_ETCDIR/locale.gen"
	command touch "$_TEST_ETCDIR/timezone"
	command mkdir -p "$_TEST_ETCDIR/env.d"
	command mkdir -p "$_TEST_ETCDIR/conf.d"
	command touch "$_TEST_ETCDIR/conf.d/hostname"
	command touch "$_TEST_ETCDIR/conf.d/keymaps"
	command mkdir -p "$_TEST_ETCDIR/systemd/network"
	command mkdir -p "$_TEST_ETCDIR/ssh"
}
_setup_etcdir

function run_configure_base_system() {
	(
		eval "$(declare -f configure_base_system | command sed "s|/etc/|$_TEST_ETCDIR/|g")"
		configure_base_system
	)
}

function run_configure_portage() {
	(
		eval "$(declare -f configure_portage | command sed "s|/etc/|$_TEST_ETCDIR/|g")"
		configure_portage
	)
}

########################################
# configure_base_system: MUSL
########################################

test_begin "configure_base_system: MUSL=true installs musl-locales"
reset_chroot_state
_setup_etcdir
MUSL=true
SYSTEMD=true
capture_output out rc run_configure_base_system
assert_eq 0 "$rc"
assert_contains "STUB:emerge" "$out"
assert_contains "musl-locales" "$out"

test_begin "configure_base_system: MUSL=false calls locale-gen"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
LOCALES="C.UTF-8 UTF-8"
capture_output out rc run_configure_base_system
assert_eq 0 "$rc"
assert_contains "STUB:locale-gen" "$out"

########################################
# configure_base_system: systemd
########################################

test_begin "configure_base_system: SYSTEMD=true calls systemd-machine-id-setup"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
capture_output out rc run_configure_base_system
assert_contains "STUB:systemd-machine-id-setup" "$out"

test_begin "configure_base_system: SYSTEMD=true sets keymap"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
KEYMAP="de-latin1"
capture_output out rc run_configure_base_system
# Check the file was written
_vconsole="$(command cat "$_TEST_ETCDIR/vconsole.conf" 2>/dev/null)"
assert_contains "KEYMAP=de-latin1" "$_vconsole"

test_begin "configure_base_system: SYSTEMD=true sets locale"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
LOCALE="en_US.UTF-8"
capture_output out rc run_configure_base_system
_localeconf="$(command cat "$_TEST_ETCDIR/locale.conf" 2>/dev/null)"
assert_contains "LANG=en_US.UTF-8" "$_localeconf"

test_begin "configure_base_system: SYSTEMD=true sets timezone via ln"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
TIMEZONE="Europe/Berlin"
capture_output out rc run_configure_base_system
assert_contains "STUB:ln" "$out"
assert_contains "Europe/Berlin" "$out"

########################################
# configure_base_system: OpenRC
########################################

test_begin "configure_base_system: SYSTEMD=false uses sed for hostname"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=false
HOSTNAME="myhost"
STAGE3_BASENAME="stage3-amd64-openrc"
capture_output out rc run_configure_base_system
assert_contains "STUB:sed" "$out"
assert_contains "hostname" "$out"

test_begin "configure_base_system: SYSTEMD=false uses sed for keymap"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=false
KEYMAP="us"
STAGE3_BASENAME="stage3-amd64-openrc"
capture_output out rc run_configure_base_system
assert_contains "STUB:sed" "$out"

test_begin "configure_base_system: SYSTEMD=false uses eselect for locale"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=false
LOCALE="C.UTF-8"
STAGE3_BASENAME="stage3-amd64-openrc"
capture_output out rc run_configure_base_system
assert_contains "STUB:eselect locale set C.UTF-8" "$out"

test_begin "configure_base_system: OpenRC+MUSL timezone via env.d"
reset_chroot_state
_setup_etcdir
MUSL=true
SYSTEMD=false
TIMEZONE="US/Eastern"
STAGE3_BASENAME="stage3-amd64-openrc"
capture_output out rc run_configure_base_system
assert_contains "STUB:emerge" "$out"
assert_contains "timezone-data" "$out"

test_begin "configure_base_system: calls env_update at end"
reset_chroot_state
_setup_etcdir
MUSL=false
SYSTEMD=true
capture_output out rc run_configure_base_system
assert_contains "STUB:env_update" "$out"

########################################
# configure_portage
########################################

test_begin "configure_portage: SELECT_MIRRORS=true calls mirrorselect"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=true
SELECT_MIRRORS_LARGE_FILE=false
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
assert_contains "STUB:mirrorselect" "$out"

test_begin "configure_portage: SELECT_MIRRORS_LARGE_FILE=true adds -D flag"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=true
SELECT_MIRRORS_LARGE_FILE=true
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
assert_contains "STUB:mirrorselect" "$out"
assert_contains "-D" "$out"

test_begin "configure_portage: SELECT_MIRRORS=false skips mirrorselect"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
assert_not_contains "STUB:mirrorselect" "$out"

test_begin "configure_portage: sets MAKEOPTS"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
assert_contains "MAKEOPTS" "$out"

test_begin "configure_portage: x86_64 installs cpuid2cpuflags"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
function uname() { echo "x86_64"; }
capture_output out rc run_configure_portage
assert_contains "cpuid2cpuflags" "$out"

test_begin "configure_portage: non-x86 skips cpuid2cpuflags"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
function uname() { echo "aarch64"; }
capture_output out rc run_configure_portage
assert_not_contains "cpuid2cpuflags" "$out"
function uname() { echo "x86_64"; }

test_begin "configure_portage: ENABLE_BINPKG=true sets FEATURES"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=true
capture_output out rc run_configure_portage
# Check the file was written
_makeconf="$(command cat "$_TEST_ETCDIR/portage/make.conf" 2>/dev/null)"
assert_contains "getbinpkg" "$_makeconf"
assert_contains "STUB:gpg" "$out"

test_begin "configure_portage: ENABLE_BINPKG=false skips binary pkg setup"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
_makeconf="$(command cat "$_TEST_ETCDIR/portage/make.conf" 2>/dev/null)"
assert_not_contains "getbinpkg" "$_makeconf"

test_begin "configure_portage: chmod 644 on make.conf"
reset_chroot_state
_setup_etcdir
SELECT_MIRRORS=false
ENABLE_BINPKG=false
capture_output out rc run_configure_portage
assert_contains "STUB:chmod 644" "$out"

# Cleanup
command rm -rf "$_TEST_ETCDIR"

test_summary
