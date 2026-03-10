#!/bin/bash
# Test runner for gentoo-install
# Usage: ./tests/run_tests.sh [test_file...]
# If no arguments given, runs all test files in tests/unit/

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED=$'\e[1;31m'
GREEN=$'\e[1;32m'
YELLOW=$'\e[1;33m'
RESET=$'\e[m'

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

function run_test_file() {
	local test_file="$1"
	local test_name
	test_name="$(basename "$test_file" .sh)"
	echo "${YELLOW}--- $test_name ---${RESET}"
	bash "$test_file"
	local rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "${RED}FAIL${RESET}: $test_name exited with code $rc"
	fi
	return $rc
}

# Collect test files
test_files=()
if [[ $# -gt 0 ]]; then
	test_files=("$@")
else
	for f in "$SCRIPT_DIR"/unit/*.sh; do
		[[ -f "$f" ]] && test_files+=("$f")
	done
fi

# --integration flag adds integration tests (requires pkexec for privilege escalation)
if [[ "${1:-}" == "--integration" ]] || [[ "${RUN_INTEGRATION:-}" == "1" ]]; then
	for f in "$SCRIPT_DIR"/integration/*.sh; do
		[[ -f "$f" ]] && test_files+=("$f")
	done
fi

if [[ ${#test_files[@]} -eq 0 ]]; then
	echo "No test files found."
	exit 1
fi

echo "Running ${#test_files[@]} test file(s)..."
echo ""

overall_rc=0
for f in "${test_files[@]}"; do
	run_test_file "$f"
	rc=$?
	[[ $rc -ne 0 ]] && overall_rc=1
	echo ""
done

# Aggregate results from test output
total=$(grep -rch '^PASS\|^FAIL' /tmp/gentoo_test_results 2>/dev/null | paste -sd+ | bc 2>/dev/null || echo "?")

if [[ $overall_rc -eq 0 ]]; then
	echo "${GREEN}All test files passed.${RESET}"
else
	echo "${RED}Some test files had failures.${RESET}"
fi
exit $overall_rc
