#!/bin/sh

set -e

cleanup() {
  rm -f "$tmpdir1" "$tmpdir2" "$tmpcommon" "$tmphash1" "$tmphash2"
}

trap cleanup EXIT INT TERM

error_exit() {
  echo "Error: $1" >&2
  exit 1
}

validate_directory() {
  if [ ! -d "$1" ]; then
    error_exit "Directory does not exist: $1"
  fi
  if [ ! -r "$1" ]; then
    error_exit "Directory is not readable: $1"
  fi
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

get_file_list() {
  dir="$1"
  output="$2"
  cd "$dir" || error_exit "Cannot change to directory: $dir"
  find . -type f ! -type l -print | sed 's|^\./||' | sort >"$output"
  cd - >/dev/null
}

compare_contents() {
  dir1="$1"
  dir2="$2"
  common_files="$3"
  hash_cmd="$4"

  tmpdir1="$5"
  tmpdir2="$6"

  while IFS= read -r file; do
    cd "$dir1" || error_exit "Cannot change to directory: $dir1"
    hash1=$($hash_cmd "$file" 2>/dev/null | awk '{print $1}')
    cd - >/dev/null

    cd "$dir2" || error_exit "Cannot change to directory: $dir2"
    hash2=$($hash_cmd "$file" 2>/dev/null | awk '{print $1}')
    cd - >/dev/null

    if [ "$hash1" != "$hash2" ]; then
      echo "$file"
    fi
  done <"$common_files"
}

main() {
  if [ $# -ne 2 ]; then
    echo "Usage: $0 <directory1> <directory2>" >&2
    exit 1
  fi

  dir1="$1"
  dir2="$2"

  validate_directory "$dir1"
  validate_directory "$dir2"

  hash_cmd=$(get_hash_command)

  tmpdir1=$(mktemp)
  tmpdir2=$(mktemp)
  tmpcommon=$(mktemp)
  tmphash1=$(mktemp)
  tmphash2=$(mktemp)

  get_file_list "$dir1" "$tmpdir1"
  get_file_list "$dir2" "$tmpdir2"

  echo "=== Files only in $dir1 ==="
  comm -23 "$tmpdir1" "$tmpdir2"

  echo ""
  echo "=== Files only in $dir2 ==="
  comm -13 "$tmpdir1" "$tmpdir2"

  echo ""
  echo "=== Files in both directories with different contents ==="
  comm -12 "$tmpdir1" "$tmpdir2" >"$tmpcommon"
  compare_contents "$dir1" "$dir2" "$tmpcommon" "$hash_cmd" "$tmphash1" "$tmphash2"

  if [ -s "$tmpdir1" ] || [ -s "$tmpdir2" ]; then
    if ! cmp -s "$tmpdir1" "$tmpdir2"; then
      exit 1
    fi
  fi

  exit 0
}

main "$@"
