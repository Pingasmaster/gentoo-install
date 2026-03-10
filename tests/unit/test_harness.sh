#!/bin/bash
# Minimal test harness for bash unit tests
# Source this from test files to get assert functions.

set -uo pipefail

_TEST_TOTAL=0
_TEST_PASSED=0
_TEST_FAILED=0
_TEST_CURRENT=""
_TEST_FAILURES=()

RED=$'\e[1;31m'
GREEN=$'\e[1;32m'
DIM=$'\e[2m'
RESET=$'\e[m'

function test_begin() {
	_TEST_CURRENT="$1"
	_TEST_TOTAL=$((_TEST_TOTAL + 1))
}

function test_pass() {
	_TEST_PASSED=$((_TEST_PASSED + 1))
	echo "  ${GREEN}PASS${RESET} ${DIM}${_TEST_CURRENT}${RESET}"
}

function test_fail() {
	_TEST_FAILED=$((_TEST_FAILED + 1))
	local msg="${1:-}"
	_TEST_FAILURES+=("${_TEST_CURRENT}: $msg")
	echo "  ${RED}FAIL${RESET} ${_TEST_CURRENT}: $msg"
}

function assert_eq() {
	local expected="$1"
	local actual="$2"
	local msg="${3:-expected '$expected', got '$actual'}"
	if [[ "$expected" == "$actual" ]]; then
		test_pass
	else
		test_fail "$msg (expected='$expected', actual='$actual')"
	fi
}

function assert_neq() {
	local not_expected="$1"
	local actual="$2"
	local msg="${3:-expected != '$not_expected', got '$actual'}"
	if [[ "$not_expected" != "$actual" ]]; then
		test_pass
	else
		test_fail "$msg"
	fi
}

function assert_match() {
	local pattern="$1"
	local actual="$2"
	local msg="${3:-expected match '$pattern'}"
	if [[ "$actual" =~ $pattern ]]; then
		test_pass
	else
		test_fail "$msg (actual='$actual')"
	fi
}

function assert_contains() {
	local needle="$1"
	local haystack="$2"
	local msg="${3:-expected to contain '$needle'}"
	if [[ "$haystack" == *"$needle"* ]]; then
		test_pass
	else
		test_fail "$msg (haystack='$haystack')"
	fi
}

function assert_not_contains() {
	local needle="$1"
	local haystack="$2"
	local msg="${3:-expected NOT to contain '$needle'}"
	if [[ "$haystack" != *"$needle"* ]]; then
		test_pass
	else
		test_fail "$msg"
	fi
}

function assert_success() {
	local msg="${1:-expected command to succeed}"
	if [[ ${PIPESTATUS[0]:-$?} -eq 0 ]]; then
		test_pass
	else
		test_fail "$msg"
	fi
}

function assert_fail() {
	local msg="${1:-expected command to fail}"
	# Caller must capture exit code before calling this
	if [[ $1 -ne 0 ]]; then
		test_pass
	else
		test_fail "expected nonzero exit, got 0"
	fi
}

# Run a command in a subshell and capture its exit code and output
# Usage: capture_output result_var exit_code_var command [args...]
function capture_output() {
	local -n _out_ref=$1
	local -n _rc_ref=$2
	shift 2
	_out_ref="$("$@" 2>&1)" && _rc_ref=0 || _rc_ref=$?
}

function test_summary() {
	echo ""
	echo "Results: ${_TEST_PASSED}/${_TEST_TOTAL} passed, ${_TEST_FAILED} failed"
	if [[ ${#_TEST_FAILURES[@]} -gt 0 ]]; then
		echo ""
		echo "${RED}Failures:${RESET}"
		for f in "${_TEST_FAILURES[@]}"; do
			echo "  - $f"
		done
	fi
	[[ $_TEST_FAILED -eq 0 ]]
}
