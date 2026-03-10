#!/bin/bash
# Tests for protection.sh and die/error handling
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$TEST_DIR")")"

########################################
# protection.sh: direct execution prevention
########################################

test_begin "protection.sh: blocks direct execution (no env var)"
out="$(bash "$PROJECT_DIR/scripts/protection.sh" 2>&1)"; rc=$?
assert_neq 0 "$rc" "should exit with error"
assert_contains "must not be executed directly" "$out"

test_begin "protection.sh: blocks when env var is wrong"
out="$(GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=false bash "$PROJECT_DIR/scripts/protection.sh" 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "must not be executed directly" "$out"

test_begin "protection.sh: allows when env var is true"
out="$(GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true bash "$PROJECT_DIR/scripts/protection.sh" 2>&1)"; rc=$?
assert_eq 0 "$rc" "should succeed when GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true"

########################################
# dispatch_chroot.sh: blocks direct execution
########################################

test_begin "dispatch_chroot.sh: blocks without EXECUTED_IN_CHROOT"
out="$(EXECUTED_IN_CHROOT=false bash "$PROJECT_DIR/scripts/dispatch_chroot.sh" 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "must not be executed directly" "$out"

########################################
# die function
########################################

test_begin "die: outputs error message to stderr"
out="$(bash -c '
	export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
	export GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
	export GENTOO_INSTALL_REPO_SCRIPT_PID=$$
	source "'"$PROJECT_DIR"'/scripts/utils.sh"
	die "test error message"
' 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "test error message" "$out"

test_begin "die_trace: includes function name"
out="$(bash -c '
	export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
	export GENTOO_INSTALL_REPO_DIR="'"$PROJECT_DIR"'"
	export GENTOO_INSTALL_REPO_SCRIPT_PID=$$
	source "'"$PROJECT_DIR"'/scripts/utils.sh"
	function my_func() { die_trace 1 "trace error message"; }
	my_func
' 2>&1)"; rc=$?
assert_neq 0 "$rc"
assert_contains "trace error message" "$out"

########################################
# elog/einfo/ewarn/eerror output
########################################

test_begin "elog: outputs message"
export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
export GENTOO_INSTALL_REPO_DIR="$PROJECT_DIR"
source "$PROJECT_DIR/scripts/utils.sh" 2>/dev/null
result="$(elog "test log message")"
assert_contains "test log message" "$result"

test_begin "einfo: outputs message"
result="$(einfo "test info message")"
assert_contains "test info message" "$result"

test_begin "ewarn: outputs to stderr"
result="$(ewarn "test warn message" 2>&1)"
assert_contains "test warn message" "$result"

test_begin "eerror: outputs to stderr"
result="$(eerror "test error" 2>&1)"
assert_contains "test error" "$result"

test_summary
