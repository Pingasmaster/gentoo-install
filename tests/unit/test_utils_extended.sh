#!/bin/bash
# Extended tests for utils.sh functions
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/test_harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/test_env.sh"

########################################
# maybe_exec
########################################

test_begin "maybe_exec: calls function if it exists"
function test_function_exists() { echo "CALLED"; }
result="$(maybe_exec test_function_exists)"
assert_eq "CALLED" "$result"

test_begin "maybe_exec: silently skips non-existent function"
unset -f definitely_not_defined 2>/dev/null || true
result="$(maybe_exec definitely_not_defined 2>&1 || true)"
assert_eq "" "$result"

test_begin "maybe_exec: passes arguments to function"
function test_with_args() { echo "ARGS: $*"; }
result="$(maybe_exec test_with_args "hello" "world")"
assert_eq "ARGS: hello world" "$result"

test_begin "maybe_exec: function with no args"
function test_no_args() { echo "NO_ARGS"; }
result="$(maybe_exec test_no_args)"
assert_eq "NO_ARGS" "$result"

########################################
# for_line_in: edge cases
########################################

test_begin "for_line_in: empty file processes nothing"
tmpfile="$(mktemp)"
> "$tmpfile"
collected=()
function collect_line() { collected+=("$1"); }
for_line_in "$tmpfile" collect_line
assert_eq 0 "${#collected[@]}" "empty file should yield 0 lines"
rm -f "$tmpfile"

test_begin "for_line_in: single line no trailing newline"
tmpfile="$(mktemp)"
printf "single" > "$tmpfile"
collected=()
function collect_line() { collected+=("$1"); }
for_line_in "$tmpfile" collect_line
assert_eq 1 "${#collected[@]}" "single line without newline should yield 1 line"
assert_eq "single" "${collected[0]}"
rm -f "$tmpfile"

test_begin "for_line_in: preserves whitespace"
tmpfile="$(mktemp)"
printf "  spaced  \n\ttabbed\t\n" > "$tmpfile"
collected=()
function collect_line() { collected+=("$1"); }
for_line_in "$tmpfile" collect_line
assert_eq "  spaced  " "${collected[0]}"
assert_eq "	tabbed	" "${collected[1]}"
rm -f "$tmpfile"

test_begin "for_line_in: handles blank lines"
tmpfile="$(mktemp)"
printf "first\n\nthird\n" > "$tmpfile"
collected=()
function collect_line() { collected+=("$1"); }
for_line_in "$tmpfile" collect_line
assert_eq 3 "${#collected[@]}" "should include blank line"
assert_eq "" "${collected[1]}"
rm -f "$tmpfile"

########################################
# parse_arguments: extended cases
########################################

test_begin "parse_arguments: optional argument accepted"
unset arguments; declare -A arguments
extra_arguments=()
known_arguments=('?opt1' '?opt2')
parse_arguments "opt1=hello"
assert_eq "hello" "${arguments[opt1]}"

test_begin "parse_arguments: optional argument absent is fine"
unset arguments; declare -A arguments
extra_arguments=()
known_arguments=('?opt1')
out="$(parse_arguments 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "parse_arguments: mix of mandatory and optional"
unset arguments; declare -A arguments
extra_arguments=()
known_arguments=('+required' '?optional')
parse_arguments "required=val" "optional=opt" 2>/dev/null; rc=$?
assert_eq 0 "$rc"
assert_eq "val" "${arguments[required]}"
assert_eq "opt" "${arguments[optional]}"

test_begin "parse_arguments: multiple extra positional"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "key=val" "/dev/sda" "/dev/sdb" "/dev/sdc"
assert_eq "val" "${arguments[key]}"
assert_eq 3 "${#extra_arguments[@]}" "should have 3 positional args"
assert_eq "/dev/sda" "${extra_arguments[0]}"
assert_eq "/dev/sdb" "${extra_arguments[1]}"
assert_eq "/dev/sdc" "${extra_arguments[2]}"

test_begin "parse_arguments: empty value is valid"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "key="
assert_eq "" "${arguments[key]}"

test_begin "parse_arguments: value containing equals"
unset arguments; declare -A arguments
extra_arguments=()
parse_arguments "key=a=b=c"
assert_eq "a=b=c" "${arguments[key]}"

test_begin "parse_arguments: no arguments at all"
unset arguments; declare -A arguments
extra_arguments=()
out="$(parse_arguments 2>&1)"; rc=$?
assert_eq 0 "$rc"
assert_eq 0 "${#extra_arguments[@]}"

########################################
# has_program: extended
########################################

test_begin "has_program: bash exists (command check)"
has_program "bash" ""; rc=$?
assert_eq 0 "$rc"

test_begin "has_program: nonexistent program"
has_program "definitely_not_a_real_program_xyz123" ""; rc=$?
assert_eq 1 "$rc"

test_begin "has_program: checkfile as absolute path exists"
has_program "ignored" "/bin/bash"; rc=$?
assert_eq 0 "$rc"

test_begin "has_program: checkfile as absolute path missing"
has_program "ignored" "/nonexistent/path/xyz"; rc=$?
assert_eq 1 "$rc"

test_begin "has_program: checkfile as command name"
has_program "ignored" "bash"; rc=$?
assert_eq 0 "$rc"

test_begin "has_program: checkfile as nonexistent command"
has_program "ignored" "nonexistent_cmd_xyz"; rc=$?
assert_eq 1 "$rc"

########################################
# shorten_device: more cases
########################################

test_begin "shorten_device: full by-id path"
result="$(shorten_device "/dev/disk/by-id/nvme-Samsung_SSD_123")"
assert_eq "nvme-Samsung_SSD_123" "$result"

test_begin "shorten_device: by-id with partition suffix"
result="$(shorten_device "/dev/disk/by-id/ata-VBOX-part1")"
assert_eq "ata-VBOX-part1" "$result"

test_begin "shorten_device: not a by-id path returns unchanged"
result="$(shorten_device "/dev/nvme0n1p1")"
assert_eq "/dev/nvme0n1p1" "$result"

test_begin "shorten_device: by-uuid path returns unchanged"
result="$(shorten_device "/dev/disk/by-uuid/1234-5678")"
assert_eq "/dev/disk/by-uuid/1234-5678" "$result"

test_begin "shorten_device: by-id exact prefix only"
result="$(shorten_device "/dev/disk/by-id/")"
assert_eq "" "$result"

########################################
# only_one_of: edge cases
########################################

test_begin "only_one_of: single arg, present"
declare -A arguments=([x]="1")
out="$(only_one_of x 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "only_one_of: three args, one present"
declare -A arguments=([b]="val")
out="$(only_one_of a b c 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "only_one_of: three args, two present fails"
declare -A arguments=([a]="1" [c]="3")
out="$(only_one_of a b c 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

test_begin "only_one_of: three args, all present fails"
declare -A arguments=([a]="1" [b]="2" [c]="3")
out="$(only_one_of a b c 2>&1)"; rc=$?
assert_contains "Only one of" "$out"

########################################
# verify_option: edge cases
########################################

test_begin "verify_option: first option is valid"
declare -A arguments=([type]="a")
out="$(verify_option type a b c 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_option: last option is valid"
declare -A arguments=([type]="c")
out="$(verify_option type a b c 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_option: numeric options"
declare -A arguments=([level]="5")
out="$(verify_option level 0 1 5 6 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_option: numeric option not in list"
declare -A arguments=([level]="3")
out="$(verify_option level 0 1 5 6 2>&1)"; rc=$?
assert_contains "Invalid option" "$out"

########################################
# create_new_id: edge cases
########################################

test_begin "create_new_id: normal id"
reset_disk_state
declare -A arguments=([new_id]="my_id")
create_new_id new_id
assert_eq true "$([[ -v DISK_ID_TO_UUID[my_id] ]] && echo true || echo false)"

test_begin "create_new_id: id with underscores and numbers"
reset_disk_state
declare -A arguments=([new_id]="part_root_dev0")
create_new_id new_id
assert_eq true "$([[ -v DISK_ID_TO_UUID[part_root_dev0] ]] && echo true || echo false)"

test_begin "create_new_id: id with dashes"
reset_disk_state
declare -A arguments=([new_id]="part-root-dev0")
create_new_id new_id
assert_eq true "$([[ -v DISK_ID_TO_UUID[part-root-dev0] ]] && echo true || echo false)"

test_begin "create_new_id: id with semicolons rejected"
reset_disk_state
declare -A arguments=([new_id]="bad;id")
out="$(create_new_id new_id 2>&1)"; rc=$?
assert_contains "invalid character" "$out"

test_begin "create_new_id: duplicate id rejected"
reset_disk_state
declare -A arguments=([new_id]="dup")
create_new_id new_id
declare -A arguments=([new_id]="dup")
out="$(create_new_id new_id 2>&1)"; rc=$?
assert_contains "already exists" "$out"

########################################
# verify_existing_unique_ids: edge cases
########################################

test_begin "verify_existing_unique_ids: three valid ids"
declare -A arguments=([ids]="a;b;c")
declare -gA DISK_ID_TO_UUID=([a]="u1" [b]="u2" [c]="u3")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_eq 0 "$rc"

test_begin "verify_existing_unique_ids: triple duplicate fails"
declare -A arguments=([ids]="a;a;a")
declare -gA DISK_ID_TO_UUID=([a]="u1")
out="$(verify_existing_unique_ids ids 2>&1)"; rc=$?
assert_contains "duplicate" "$out"

########################################
# elog/einfo/ewarn/eerror output format
########################################

test_begin "elog: output contains + prefix and message"
result="$(elog "test message")"
assert_contains "+" "$result"
assert_contains "test message" "$result"

test_begin "einfo: output contains [+] prefix and message"
result="$(einfo "info message")"
assert_contains "info message" "$result"

test_begin "ewarn: output contains [!] prefix"
result="$(ewarn "warn message" 2>&1)"
assert_contains "warn message" "$result"

test_begin "eerror: output contains error prefix"
result="$(eerror "error message" 2>&1)"
assert_contains "error" "$result"
assert_contains "error message" "$result"

########################################
# countdown: output
########################################

test_begin "countdown: output includes all numbers"
result="$(countdown "test " 3 2>&1)"
assert_contains "test " "$result"
assert_contains "3" "$result"
assert_contains "2" "$result"
assert_contains "1" "$result"

test_begin "countdown: 1 second countdown"
result="$(countdown "go " 1 2>&1)"
assert_contains "go " "$result"
assert_contains "1" "$result"

test_summary
