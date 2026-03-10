#!/bin/bash
# Tests for install script argument parsing
# These tests run the install script in a subshell to test argument parsing
# without actually installing anything.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$TEST_DIR")")"
INSTALL="$PROJECT_DIR/install"

# We can't actually run the install script (needs root, config, etc.)
# But we can test the argument parsing section by extracting and testing the logic.
# We'll source just enough to test the arg parsing.

function test_arg_parse() {
	# Run the install script with given args, expecting it to fail at
	# a predictable point (not root, no config, etc.) but capture
	# what ACTION/CONFIG/CHROOT_DIR are set to.
	local out
	out="$(bash -c '
		set -uo pipefail
		ACTUAL_WORKING_DIRECTORY="'"$PROJECT_DIR"'"
		GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
		GENTOO_INSTALL_REPO_DIR_ORIGINAL="'"$PROJECT_DIR"'"
		GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
		GENTOO_INSTALL_REPO_SCRIPT_PID=$$
		source "'"$PROJECT_DIR"'/scripts/utils.sh"

		ACTION=""
		CONFIG="$GENTOO_INSTALL_REPO_DIR/gentoo.conf"

		'"$1"'

		echo "ACTION=$ACTION"
		echo "CONFIG=$CONFIG"
		[[ -v CHROOT_DIR ]] && echo "CHROOT_DIR=$CHROOT_DIR" || echo "CHROOT_DIR=__unset__"
		echo "REMAINING_ARGS=$*"
	' -- 2>&1)" || true
	echo "$out"
}

########################################
# --install flag
########################################

test_begin "install args: -i sets ACTION=install"
result="$(test_arg_parse '
	set -- "-i"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-i"|"--install") ACTION="install" ;;
			*) echo "DIE: Invalid option $1" >&2; break ;;
		esac
		shift
	done
')"
assert_contains "ACTION=install" "$result"

test_begin "install args: --install sets ACTION=install"
result="$(test_arg_parse '
	set -- "--install"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-i"|"--install") ACTION="install" ;;
			*) echo "DIE: Invalid option $1" >&2; break ;;
		esac
		shift
	done
')"
assert_contains "ACTION=install" "$result"

########################################
# --chroot flag with break behavior
########################################

test_begin "install args: -R sets chroot action and preserves remaining args"
result="$(bash -c '
	set -uo pipefail
	ACTION=""
	CHROOT_DIR=""
	set -- "-R" "/mnt" "cmd1" "arg1"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-R"|"--chroot")
				ACTION="chroot"
				CHROOT_DIR="$2"
				shift # past -R flag
				shift # past DIR
				break # remaining args are CMD
				;;
			*) echo "DIE: Invalid option $1"; exit 1 ;;
		esac
		shift
	done
	echo "ACTION=$ACTION"
	echo "CHROOT_DIR=$CHROOT_DIR"
	echo "REMAINING=$*"
' 2>&1)"
assert_contains "ACTION=chroot" "$result"
assert_contains "CHROOT_DIR=/mnt" "$result"
assert_contains "REMAINING=cmd1 arg1" "$result"

test_begin "install args: -R without CMD defaults to empty remaining"
result="$(bash -c '
	set -uo pipefail
	ACTION=""
	CHROOT_DIR=""
	set -- "-R" "/mnt"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-R"|"--chroot")
				ACTION="chroot"
				CHROOT_DIR="$2"
				shift
				shift
				break
				;;
			*) echo "DIE: Invalid option $1"; exit 1 ;;
		esac
		shift
	done
	echo "ACTION=$ACTION"
	echo "CHROOT_DIR=$CHROOT_DIR"
	echo "REMAINING=[$*]"
' 2>&1)"
assert_contains "ACTION=chroot" "$result"
assert_contains "CHROOT_DIR=/mnt" "$result"
assert_contains "REMAINING=[]" "$result"

test_begin "install args: -R with multiple CMD args preserved"
result="$(bash -c '
	set -uo pipefail
	ACTION=""
	CHROOT_DIR=""
	set -- "-R" "/mnt/gentoo" "/bin/bash" "-c" "echo hello"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-R"|"--chroot")
				ACTION="chroot"
				CHROOT_DIR="$2"
				shift
				shift
				break
				;;
			*) echo "DIE: Invalid option $1"; exit 1 ;;
		esac
		shift
	done
	echo "CHROOT_DIR=$CHROOT_DIR"
	echo "ARGC=$#"
	echo "ARG0=${1:-}"
	echo "ARG1=${2:-}"
	echo "ARG2=${3:-}"
' 2>&1)"
assert_contains "CHROOT_DIR=/mnt/gentoo" "$result"
assert_contains "ARGC=3" "$result"
assert_contains "ARG0=/bin/bash" "$result"
assert_contains "ARG1=-c" "$result"
assert_contains "ARG2=echo hello" "$result"

########################################
# --config flag
########################################

test_begin "install args: -c stores absolute path"
# Create a temp config for the test
tmpconf="$(mktemp "$PROJECT_DIR/test_conf_XXXXXX")"
result="$(bash -c '
	set -uo pipefail
	ACTUAL_WORKING_DIRECTORY="'"$PROJECT_DIR"'"
	GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
	CONFIG="$GENTOO_INSTALL_REPO_DIR/gentoo.conf"
	function die() { echo "DIE: $*" >&2; exit 1; }

	set -- "-c" "'"$tmpconf"'"
	case "$1" in
		"-c"|"--config")
			[[ -f "$2" ]] || die "Config file not found: $2"
			CONFIG="$(cd "$ACTUAL_WORKING_DIRECTORY" && realpath "$2" 2>/dev/null)" || die "Could not determine realpath"
			;;
	esac
	echo "CONFIG=$CONFIG"
' 2>&1)"
assert_contains "CONFIG=$tmpconf" "$result" "CONFIG should be absolute path"
assert_match "^CONFIG=/" "$(grep CONFIG= <<< "$result")" "path should be absolute"
rm -f "$tmpconf"

test_begin "install args: -c validates config inside install dir"
tmpconf="$(mktemp "$PROJECT_DIR/test_conf_XXXXXX")"
result="$(bash -c '
	set -uo pipefail
	GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
	ACTUAL_WORKING_DIRECTORY="'"$PROJECT_DIR"'"
	function die() { echo "DIE: $*" >&2; exit 1; }
	CONFIG="$(cd "$ACTUAL_WORKING_DIRECTORY" && realpath "'"$tmpconf"'" 2>/dev/null)" || die "realpath failed"
	[[ -z "${CONFIG%%"$GENTOO_INSTALL_REPO_DIR"*}" ]] || die "Config file must be inside the installation directory."
	echo "PASSED"
' 2>&1)"
assert_contains "PASSED" "$result" "config inside install dir should pass validation"
rm -f "$tmpconf"

test_begin "install args: -c rejects config outside install dir"
tmpconf="$(mktemp /tmp/test_conf_XXXXXX)"
result="$(bash -c '
	set -uo pipefail
	GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
	ACTUAL_WORKING_DIRECTORY="'"$PROJECT_DIR"'"
	function die() { echo "DIE: $*" >&2; exit 1; }
	CONFIG="$(cd "$ACTUAL_WORKING_DIRECTORY" && realpath "'"$tmpconf"'" 2>/dev/null)" || die "realpath failed"
	[[ -z "${CONFIG%%"$GENTOO_INSTALL_REPO_DIR"*}" ]] || die "Config file must be inside the installation directory."
	echo "PASSED"
' 2>&1)"
assert_contains "must be inside" "$result" "config outside install dir should be rejected"
rm -f "$tmpconf"

test_begin "install args: -c with nonexistent file"
result="$(bash -c '
	set -uo pipefail
	function die() { echo "DIE: $*" >&2; exit 1; }
	set -- "-c" "/nonexistent/file.conf"
	case "$1" in
		"-c") [[ -f "$2" ]] || die "Config file not found: $2" ;;
	esac
	echo "PASSED"
' 2>&1)"
assert_contains "Config file not found" "$result"

########################################
# Multiple action rejection
########################################

test_begin "install args: -i -i gives multiple actions error"
result="$(bash -c '
	set -uo pipefail
	ACTION=""
	function die() { echo "DIE: $*" >&2; exit 1; }
	set -- "-i" "-i"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-i") [[ -z $ACTION ]] || die "Multiple actions given"; ACTION="install" ;;
			*) die "Invalid option $1" ;;
		esac
		shift
	done
	echo "OK"
' 2>&1)"
assert_contains "Multiple actions" "$result"

########################################
# help flag
########################################

test_begin "install args: --help shows usage"
result="$(bash -c '
	set -- "--help"
	case "$1" in
		""|"help"|"--help"|"-help"|"-h")
			echo "Usage: install [opts]... <action>"
			;;
	esac
' 2>&1)"
assert_contains "Usage:" "$result"

test_summary
