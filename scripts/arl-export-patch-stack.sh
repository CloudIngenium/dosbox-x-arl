#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-dosbox-x-v2026.07.02}"
out_dir="${2:-arl-patches}"

mkdir -p "$out_dir"

base_commit="$(git rev-parse "$base_ref")"
head_commit="$(git rev-parse HEAD)"

git format-patch "$base_ref..HEAD" -o "$out_dir"

{
	echo "base_ref=$base_ref"
	echo "base_commit=$base_commit"
	echo "head_commit=$head_commit"
	echo
	echo "arl_patch_commits:"
	git log --reverse --format='  %H %s' "$base_ref..HEAD"
	echo
	echo "watched_serial_files_changed:"
	git diff --name-only "$base_ref..HEAD" -- \
		src/hardware/serialport/directserial.cpp \
		src/hardware/serialport/directserial.h \
		src/hardware/serialport/serialport.cpp \
		src/dosbox.cpp \
		dosbox-x.reference.conf \
		dosbox-x.reference.full.conf | sed 's/^/  /'
} > "$out_dir/manifest.txt"
