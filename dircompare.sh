#!/bin/sh

# MIT License
#
# Copyright (c) 2025 Kamil Jiwa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -eu

FILES_DIR1=""
FILES_DIR2=""
FILES_COMMON=""
FILES_DIFF1=""
FILES_DIFF2=""
DIFFERENCES_FOUND=0

error_exit() {
  echo "Error: $1" >&2
  exit 1
}

create_temp_files() {
  tmpdir="${TMPDIR:-/tmp}"
  FILES_DIR1="${tmpdir}/dircompare_dir1.$$"
  FILES_DIR2="${tmpdir}/dircompare_dir2.$$"
  FILES_COMMON="${tmpdir}/dircompare_common.$$"
  FILES_DIFF1="${tmpdir}/dircompare_diff1.$$"
  FILES_DIFF2="${tmpdir}/dircompare_diff2.$$"

  : >"$FILES_DIR1" || error_exit "Failed to create temporary file"
  : >"$FILES_DIR2" || error_exit "Failed to create temporary file"
  : >"$FILES_COMMON" || error_exit "Failed to create temporary file"
  : >"$FILES_DIFF1" || error_exit "Failed to create temporary file"
  : >"$FILES_DIFF2" || error_exit "Failed to create temporary file"
}

cleanup() {
  [ -n "$FILES_DIR1" ] && rm -f "$FILES_DIR1"
  [ -n "$FILES_DIR2" ] && rm -f "$FILES_DIR2"
  [ -n "$FILES_COMMON" ] && rm -f "$FILES_COMMON"
  [ -n "$FILES_DIFF1" ] && rm -f "$FILES_DIFF1"
  [ -n "$FILES_DIFF2" ] && rm -f "$FILES_DIFF2"
}

trap cleanup EXIT INT TERM

usage() {
  cat <<EOF
Usage: $0 [-x|--exclude <pattern>]... <directory1> <directory2>

  Compares two directories and reports differences in files and content.

  Arguments:
    <directory1>      First directory to compare.
    <directory2>      Second directory to compare.
    -x, --exclude     Pattern to exclude from comparison. Can be specified multiple times.
    -h                Display this help message.

EOF
  exit 1
}

validate_input() {
  input="$1"
  type="$2"

  case "$input" in
  *[\'\"]*) error_exit "Invalid characters in $type: $input" ;;
  esac
}

validate_directory() {
  dir="$1"
  [ -d "$dir" ] || error_exit "Directory does not exist: $dir"
  [ -r "$dir" ] || error_exit "Directory is not readable: $dir"
}

get_hash_command() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    error_exit "Neither sha256sum nor shasum found"
  fi
}

build_exclusion_args() {
  exclusions="$1"
  base_dir="$2"

  [ -z "$exclusions" ] && return

  old_ifs="$IFS"
  IFS="|"

  for pattern in $exclusions; do
    set -- "$@" -path "$base_dir/$pattern" -prune -o
  done

  IFS="$old_ifs"
}

get_file_list() {
  dir="$1"
  output="$2"
  exclusions="$3"

  abs_dir=$(cd "$dir" && pwd) || error_exit "Cannot access directory: $dir"

  set -- "$abs_dir"
  build_exclusion_args "$exclusions" "$abs_dir"
  set -- "$@" -type f -print

  find "$@" | sed "s|^$abs_dir/||" | sort >"$output" || error_exit "Find command failed"
}

compute_hash() {
  file="$1"
  hash_cmd="$2"
  $hash_cmd "$file" 2>/dev/null | awk '{print $1}'
}

compare_contents() {
  dir1="$1"
  dir2="$2"
  common_files="$3"
  hash_cmd="$4"

  abs_dir1=$(cd "$dir1" && pwd)
  abs_dir2=$(cd "$dir2" && pwd)

  while IFS= read -r file; do
    hash1=$(compute_hash "$abs_dir1/$file" "$hash_cmd")
    hash2=$(compute_hash "$abs_dir2/$file" "$hash_cmd")

    if [ "$hash1" != "$hash2" ]; then
      echo "$file"
      DIFFERENCES_FOUND=1
    fi
  done <"$common_files"
}

show_files_only_in_dir1() {
  dir1="$1"

  comm -23 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_DIFF1"

  echo "=== Files only in $dir1 ==="
  if grep -q . "$FILES_DIFF1"; then
    cat "$FILES_DIFF1"
    DIFFERENCES_FOUND=1
  fi
  echo ""
}

show_files_only_in_dir2() {
  dir2="$1"

  comm -13 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_DIFF2"

  echo "=== Files only in $dir2 ==="
  if grep -q . "$FILES_DIFF2"; then
    cat "$FILES_DIFF2"
    DIFFERENCES_FOUND=1
  fi
  echo ""
}

show_files_with_different_contents() {
  dir1="$1"
  dir2="$2"
  hash_cmd="$3"

  echo "=== Files in both directories with different contents ==="
  comm -12 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_COMMON"
  compare_contents "$dir1" "$dir2" "$FILES_COMMON" "$hash_cmd"
}

show_differences() {
  dir1="$1"
  dir2="$2"
  hash_cmd="$3"

  show_files_only_in_dir1 "$dir1"
  show_files_only_in_dir2 "$dir2"
  show_files_with_different_contents "$dir1" "$dir2" "$hash_cmd"
}

parse_args() {
  exclusions=""

  while [ $# -gt 0 ]; do
    case "$1" in
    -h) usage ;;
    -x | --exclude)
      [ -n "${2:-}" ] || error_exit "Option $1 requires an argument"
      validate_input "$2" "exclusion pattern"
      exclusions="${exclusions:+$exclusions|}$2"
      shift 2
      ;;
    -*)
      error_exit "Unknown option: $1"
      ;;
    *)
      break
      ;;
    esac
  done

  [ $# -eq 2 ] || usage

  dir1="$1"
  dir2="$2"

  validate_directory "$dir1"
  validate_directory "$dir2"

  echo "$exclusions|$dir1|$dir2"
}

main() {
  result=$(parse_args "$@")

  old_ifs="$IFS"
  IFS="|"
  set -- $result
  IFS="$old_ifs"

  exclusions="$1"
  dir1="$2"
  dir2="$3"

  hash_cmd=$(get_hash_command)
  create_temp_files

  get_file_list "$dir1" "$FILES_DIR1" "$exclusions"
  get_file_list "$dir2" "$FILES_DIR2" "$exclusions"

  show_differences "$dir1" "$dir2" "$hash_cmd"

  exit $DIFFERENCES_FOUND
}

main "$@"
