#!/bin/sh

set -e

tmpdir1=""
tmpdir2=""
tmpcommon=""
tmphash1=""
tmphash2=""
differences_found=0

cleanup() {
  [ -n "$tmpdir1" ] && rm -f "$tmpdir1"
  [ -n "$tmpdir2" ] && rm -f "$tmpdir2"
  [ -n "$tmpcommon" ] && rm -f "$tmpcommon"
  [ -n "$tmphash1" ] && rm -f "$tmphash1"
  [ -n "$tmphash2" ] && rm -f "$tmphash2"
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
  [ -d "$1" ] || error_exit "Directory does not exist: $1"
  [ -r "$1" ] || error_exit "Directory is not readable: $1"
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
      differences_found=1
    fi
  done <"$common_files"
}

main() {
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

  [ $# -eq 2 ] || usage

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

  get_file_list "$dir1" "$tmpdir1" "$exclusions"
  get_file_list "$dir2" "$tmpdir2" "$exclusions"

  echo "=== Files only in $dir1 ==="
  if comm -23 "$tmpdir1" "$tmpdir2" | grep -q .; then
    comm -23 "$tmpdir1" "$tmpdir2"
    differences_found=1
  fi

  echo ""
  echo "=== Files only in $dir2 ==="
  if comm -13 "$tmpdir1" "$tmpdir2" | grep -q .; then
    comm -13 "$tmpdir1" "$tmpdir2"
    differences_found=1
  fi

  echo ""
  echo "=== Files in both directories with different contents ==="
  comm -12 "$tmpdir1" "$tmpdir2" >"$tmpcommon"
  compare_contents "$dir1" "$dir2" "$tmpcommon" "$hash_cmd"

  exit $differences_found
}

main "$@"
