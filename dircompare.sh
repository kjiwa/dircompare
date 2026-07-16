#!/bin/sh
# shellcheck disable=SC3043  # local: supported by dash, bash, and macOS /bin/sh

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

NL='
'
readonly NL

WORK_DIR=""
FILES_DIR1=""
FILES_DIR2=""
FILES_COMMON=""
DIR1=""
DIR2=""
EXCLUSIONS=""
COMPARE_MODE="hash"
HASH_CMD=""
SIZE_CMD=""
DIFFERENCES_FOUND=0

error_exit() {
  echo "Error: $1" >&2
  exit 2
}

# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<EOF
Usage: $0 [-x|--exclude <pattern>]... [-c|--compare <hash|size>] <directory1> <directory2>

  Compares two directories and reports differences in files and content.

  Arguments:
    <directory1>      First directory to compare.
    <directory2>      Second directory to compare.
    -x, --exclude     Pattern to exclude from comparison. Can be specified multiple times.
    -c, --compare     Comparison mode for files present in both directories:
                      'hash' (default) compares SHA-256 of contents;
                      'size' compares file sizes only (never reads file contents;
                      useful for cloud/network mounts where reads are expensive).
    -h, --help        Display this help message.

  Exit status:
    0  directories match
    1  differences found
    2  error

EOF
}

validate_directory() {
  local dir="$1"
  [ -d "$dir" ] || error_exit "Directory does not exist: $dir"
  [ -r "$dir" ] || error_exit "Directory is not readable: $dir"
}

set_hash_command() {
  if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD="shasum -a 256"
  else
    error_exit "Neither sha256sum nor shasum found"
  fi
  readonly HASH_CMD
}

set_size_command() {
  if stat -c %s / >/dev/null 2>&1; then
    SIZE_CMD="stat -c %s" # GNU coreutils
  elif stat -f %z / >/dev/null 2>&1; then
    SIZE_CMD="stat -f %z" # BSD / macOS
  else
    error_exit "No supported stat command found for size comparison"
  fi
  readonly SIZE_CMD
}

create_temp_files() {
  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dircompare.XXXXXX") ||
    error_exit "Failed to create temporary directory"
  FILES_DIR1="$WORK_DIR/list1"
  FILES_DIR2="$WORK_DIR/list2"
  FILES_COMMON="$WORK_DIR/common"
  readonly WORK_DIR FILES_DIR1 FILES_DIR2 FILES_COMMON
}

# find arguments accumulate in the positional parameters; POSIX sh has no arrays.
get_file_list() {
  local dir="$1" output="$2" old_ifs pattern

  set -- .
  if [ -n "$EXCLUSIONS" ]; then
    old_ifs="$IFS"
    IFS="$NL"
    set -f
    for pattern in $EXCLUSIONS; do
      # Trailing slash stripped: documented patterns like "env/" must match
      # find paths, which have no trailing slash.
      set -- "$@" -path "./${pattern%/}" -prune -o
    done
    set +f
    IFS="$old_ifs"
  fi
  set -- "$@" -type f -print

  (cd -- "$dir" && find "$@") | sed 's|^\./||' | sort >"$output"
}

show_only_in() {
  local comm_flags="$1" dir="$2" only

  only=$(comm "$comm_flags" "$FILES_DIR1" "$FILES_DIR2")

  echo "=== Files only in $dir ==="
  if [ -n "$only" ]; then
    printf '%s\n' "$only"
    DIFFERENCES_FOUND=1
  fi
  echo ""
}

file_signature() {
  # HASH_CMD / SIZE_CMD are deliberately unquoted: they contain arguments
  # (e.g. "shasum -a 256" or "stat -c %s").
  if [ "$COMPARE_MODE" = "size" ]; then
    $SIZE_CMD -- "$1"
  else
    $HASH_CMD -- "$1" | awk '{print $1}'
  fi
}

show_content_diffs() {
  local file sig1 sig2 header

  if [ "$COMPARE_MODE" = "size" ]; then
    header="=== Files in both directories with different sizes ==="
  else
    header="=== Files in both directories with different contents ==="
  fi
  echo "$header"
  comm -12 "$FILES_DIR1" "$FILES_DIR2" >"$FILES_COMMON"

  while IFS= read -r file; do
    sig1=$(file_signature "$DIR1/$file")
    sig2=$(file_signature "$DIR2/$file")

    if [ -z "$sig1" ] || [ -z "$sig2" ]; then
      error_exit "Failed to stat/hash file: $file"
    fi

    if [ "$sig1" != "$sig2" ]; then
      printf '%s\n' "$file"
      DIFFERENCES_FOUND=1
    fi
  done <"$FILES_COMMON"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -x | --exclude)
      [ -n "${2:-}" ] || error_exit "Option $1 requires an argument"
      case "$2" in
      *"$NL"*) error_exit "Exclusion pattern must not contain a newline" ;;
      esac
      EXCLUSIONS="${EXCLUSIONS:+$EXCLUSIONS$NL}$2"
      shift 2
      ;;
    -c | --compare)
      [ -n "${2:-}" ] || error_exit "Option $1 requires an argument"
      case "$2" in
      hash | size) ;;
      *) error_exit "Invalid compare mode: $2 (expected 'hash' or 'size')" ;;
      esac
      COMPARE_MODE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      error_exit "Unknown option: $1"
      ;;
    *)
      break
      ;;
    esac
  done

  [ $# -eq 2 ] || {
    usage >&2
    exit 2
  }

  DIR1="$1"
  DIR2="$2"
  readonly DIR1 DIR2 EXCLUSIONS COMPARE_MODE

  validate_directory "$DIR1"
  validate_directory "$DIR2"
}

main() {
  parse_args "$@"
  if [ "$COMPARE_MODE" = "size" ]; then
    set_size_command
  else
    set_hash_command
  fi
  create_temp_files

  get_file_list "$DIR1" "$FILES_DIR1"
  get_file_list "$DIR2" "$FILES_DIR2"

  show_only_in -23 "$DIR1"
  show_only_in -13 "$DIR2"
  show_content_diffs

  exit "$DIFFERENCES_FOUND"
}

main "$@"
