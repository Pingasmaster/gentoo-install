#!/bin/bash
set -uo pipefail

[[ $EXECUTED_IN_CHROOT != "true" ]] \
	&& { echo "This script must not be executed directly!" >&2; exit 1; }

# Source the systems profile
source /etc/profile

# Set safe umask
umask 0077

# Export variables (used to determine processor count by some applications)
export NPROC="$(nproc || echo 2)"
export NPROC_ONE="$((NPROC + 1))"

# Compute RAM-aware job count: 2 GiB per thread
_mem_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null) || _mem_kb=0
_mem_gib=$(( (_mem_kb + 524288) / 1048576 ))
_max_jobs=$(( _mem_gib / 2 ))
[[ $_max_jobs -lt 1 ]] && _max_jobs=1
[[ $_max_jobs -gt $NPROC ]] && _max_jobs=$NPROC

# Set default makeflags and emerge flags for parallel emerges
export MAKEFLAGS="-j$_max_jobs -l$NPROC"
export EMERGE_DEFAULT_OPTS="--jobs=$_max_jobs --load-average=$NPROC"

# Unset critical variables
unset key

# Execute the requested command
exec "$@"
