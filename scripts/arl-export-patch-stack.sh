#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-dosbox-x-v2026.07.02}"
out_dir="${2:-arl-patches}"

rm -rf "$out_dir"
mkdir -p "$out_dir"

requested_base_commit="$(git rev-parse "$base_ref")"
base_commit="$(git merge-base "$base_ref" HEAD)"
head_commit="$(git rev-parse HEAD)"
range="$base_commit..HEAD"

git format-patch --no-binary "$range" -o "$out_dir"

{
	echo "base_ref=$base_ref"
	echo "requested_base_commit=$requested_base_commit"
	echo "base_commit=$base_commit"
	echo "head_commit=$head_commit"
	echo
	echo "arl_patch_commits:"
	git log --reverse --format='  %H %s' "$range"
	echo
	echo "watched_serial_files_changed:"
	git diff --name-only "$range" -- \
		src/hardware/serialport/directserial.cpp \
		src/hardware/serialport/directserial.h \
		src/hardware/serialport/serialport.cpp \
		src/dosbox.cpp \
		dosbox-x.reference.conf \
		dosbox-x.reference.full.conf | sed 's/^/  /'
} > "$out_dir/manifest.txt"
