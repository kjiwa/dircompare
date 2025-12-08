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

set -e

FILES_DIR1=""
FILES_DIR2=""
FILES_COMMON=""
FILES_DIFF1=""
FILES_DIFF2=""
DIFFERENCES_FOUND=0

get_temp_dir() {
  echo "${TMPDIR:-/tmp}"
}

create_temp_file() {
  tmpfile="$1"
  : >"$tmpfile" || error_exit "Failed to create temporary file"
}

init_temp_files() {
  tmpdir=$(get_temp_dir)
  FILES_DIR1="${tmpdir}/dircompare1.$"
  FILES_DIR2="${tmpdir}/dircompare2.$"
  FILES_COMMON="${tmpdir}/dircomparecommon.$"
  FILES_DIFF1="${tmpdir}/dircomparediff1.$"
  FILES_DIFF2="${tmpdir}/dircomparediff2.$"

  create_temp_file "$FILES_DIR1"
  create_temp_file "$FILES_DIR2"
  create_temp_file "$FILES_COMMON"
  create_temp_file "$FILES_DIFF1"
  create_temp_file "$FILES_DIFF2"
}

cleanup() {
  [ -n "$FILES_DIR1" ] && rm -f "$FILES_DIR1"
  [ -n "$FILES_DIR2" ] && rm -f "$FILES_DIR2"
  [ -n "$FILES_COMMON" ] && rm -f "$FILES_COMMON"
  [ -n "$FILES_DIFF1" ] && rm -f "$FILES_DIFF1"
  [ -n "$FILES_DIFF2" ] && rm -f "$FILES_DIFF2"
}

trap cleanup EXIT INT TERM

error_exit() {
  echo "Error: $1" >&2
  exit 1
}

usage() {
  echo "Usage: $0 [-x|--exclude <pattern>]... <directory1> <directory2>" >&2
  exit 1
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

build_find_exclusions() {
  exclusions="$1"
  [ -z "$exclusions" ] && return

  result=""
  old_ifs="$IFS"
  IFS="|"
  for pattern in $exclusions; do
    [ -n "$result" ] && result="$result -o"
    result="$result -path ./$pattern -prune"
  done
  IFS="$old_ifs"
  echo "$result -o"
}

get_file_list() {
  dir="$1"
  output="$2"
  exclusions="$3"

  cd "$dir" || error_exit "Cannot change to directory: $dir"

  find_exclusions=$(build_find_exclusions "$exclusions")

  if [ -n "$find_exclusions" ]; then
    eval "find . $find_exclusions -type f -print" | sed 's|^\./||' | sort >"$output"
  else
    find . -type f -print | sed 's|^\./||' | sort >"$output"
  fi

  cd - >/dev/null
}

compare_contents() {
  dir1="$1"
  dir2="$2"
  common_files="$3"
  hash_cmd="$4"

  while IFS= read -r file; do
    cd "$dir1" || error_exit "Cannot change to directory: $dir1"
    hash1=$($hash_cmd "$file" 2>/dev/null | awk '{print $1}')
    cd - >/dev/null

    cd "$dir2" || error_exit "Cannot change to directory: $dir2"
    hash2=$($hash_cmd "$file" 2>/dev/null | awk '{print $1}')
    cd - >/dev/null

    if [ "$hash1" != "$hash2" ]; then
      echo "$file"
      DIFFERENCES_FOUND=1
    fi
  done <"$common_files"
}

show_unique_files() {
  label="$1"
  file_list="$2"

  echo "=== $label ==="
  if grep -q . "$file_list"; then
    cat "$file_list"
    DIFFERENCES_FOUND=1
  fi
}

parse_exclusions() {
  exclusions=""
  while [ $# -gt 0 ]; do
    case "$1" in
    -x | --exclude)
      [ -n "$2" ] || error_exit "Option $1 requires an argument"
      if [ -z "$exclusions" ]; then
        exclusions="$2"
      else
        exclusions="$exclusions|$2"
      fi
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
  echo "$exclusions"
}

skip_parsed_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
    -x | --exclude) shift 2 ;;
    -*) shift ;;
    *) break ;;
    esac
  done
  echo "$@"
}

validate_args() {
  [ $# -eq 2 ] || usage
}

show_files_only_in_dir1() {
  dir1="$1"
  comm -23 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_DIFF1"
  show_unique_files "Files only in $dir1" "$FILES_DIFF1"
}

show_files_only_in_dir2() {
  dir2="$1"
  comm -13 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_DIFF2"
  show_unique_files "Files only in $dir2" "$FILES_DIFF2"
}

show_files_with_different_contents() {
  dir1="$1"
  dir2="$2"
  hash_cmd="$3"

  echo "=== Files in both directories with different contents ==="
  comm -12 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_COMMON"
  compare_contents "$dir1" "$dir2" "$FILES_COMMON" "$hash_cmd"
}

compare_directories() {
  dir1="$1"
  dir2="$2"
  hash_cmd="$3"

  show_files_only_in_dir1 "$dir1"
  echo ""
  show_files_only_in_dir2 "$dir2"
  echo ""
  show_files_with_different_contents "$dir1" "$dir2" "$hash_cmd"
}

main() {
  exclusions=$(parse_exclusions "$@")
  set -- $(skip_parsed_options "$@")
  validate_args "$@"

  dir1="$1"
  dir2="$2"

  validate_directory "$dir1"
  validate_directory "$dir2"

  hash_cmd=$(get_hash_command)
  init_temp_files

  get_file_list "$dir1" "$FILES_DIR1" "$exclusions"
  get_file_list "$dir2" "$FILES_DIR2" "$exclusions"

  compare_directories "$dir1" "$dir2" "$hash_cmd"

  exit $DIFFERENCES_FOUND
}

main "$@"
