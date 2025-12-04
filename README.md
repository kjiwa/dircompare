# Directory Comparison Tool

A POSIX-compliant shell script that compares two directories and identifies differences.

## Usage

```bash
./dircompare.sh <directory1> <directory2>
```

## Output

The tool produces three sections:

1. **Files only in directory1** - Files present in the first directory but not in the second
2. **Files only in directory2** - Files present in the second directory but not in the first
3. **Files in both directories with different contents** - Files that exist in both locations but have different content

## Exit Codes

- `0` - Directories are identical
- `1` - Differences found or error occurred

## Requirements

- POSIX-compliant shell (sh, bash, dash, etc.)
- Standard utilities: `find`, `sort`, `comm`, `awk`, `sed`
- Hash utility: `sha256sum` (Linux) or `shasum` (macOS)

## Installation

```bash
chmod +x dircompare.sh
```

Optionally, move to a directory in your PATH:

```bash
sudo mv dircompare.sh /usr/local/bin/dircompare
```

## Examples

Compare two directories:
```bash
./dircompare.sh /path/to/backup /path/to/original
```

Use in scripts:
```bash
if ./dircompare.sh dir1 dir2; then
    echo "Directories are identical"
else
    echo "Differences found"
fi
```

## Limitations

- Symlinks are skipped (not followed)
- Requires read permissions on both directories
- Content comparison uses SHA-256 hashing

## Compatibility

Tested on:
- Linux (various distributions)
- macOS
- BSD systems
