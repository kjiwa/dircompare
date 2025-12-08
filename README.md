# Directory Comparison Tool

A POSIX-compliant shell script that compares two directories and identifies differences.

## Usage

```bash
./dircompare.sh [-x|--exclude <pattern>]... <directory1> <directory2>
```

### Options

- `-x <pattern>`, `--exclude <pattern>` - Exclude directories matching the pattern (can be specified multiple times)

### Arguments

- `directory1` - First directory to compare
- `directory2` - Second directory to compare

## Requirements

- POSIX-compliant shell (sh, bash, dash, etc.)
- Standard utilities: `find`, `sort`, `comm`, `awk`, `sed`
- Hash utility: `sha256sum` (Linux) or `shasum` (macOS)

## Output

The tool produces three sections:

1. **Files only in directory1** - Files present in the first directory but not in the second
2. **Files only in directory2** - Files present in the second directory but not in the first
3. **Files in both directories with different contents** - Files that exist in both locations but have different content

## Exit Codes

- `0` - Directories are identical
- `1` - Differences found or error occurred

## Examples

Compare two directories:
```bash
./dircompare.sh /path/to/backup /path/to/original
```

Exclude specific directories:
```bash
./dircompare.sh -x env/ -x .git/ dir1 dir2
./dircompare.sh --exclude node_modules/ --exclude __pycache__/ dir1 dir2
```

Exclude multiple directories with different patterns:
```bash
./dircompare.sh -x .git/ -x build/ -x dist/ project1 project2
```

Use in scripts:
```bash
if ./dircompare.sh -x venv/ dir1 dir2; then
    echo "Directories are identical"
else
    echo "Differences found"
fi
```

## Exclusion Patterns

- Patterns are relative paths from the comparison root
- Use trailing slashes for directory names (e.g., `env/`, `node_modules/`)
- Patterns can include subdirectories (e.g., `src/generated/`)
- Exclusions apply to both directories being compared

## Limitations

- Symlinks are skipped (not followed or compared)
- Requires read permissions on both directories
- Content comparison uses SHA-256 hashing (files are not compared byte-by-byte)
- Large files may take time to hash

## Comparison with diff -qr

This tool provides a structured alternative to `diff -qr directory1 directory2` with several key differences:

### Functional Differences

**Output Format:**
- `diff -qr`: Mixed output listing all differences together
- This tool: Three distinct sections (only in dir1, only in dir2, different contents)

**Exclusion Patterns:**
- `diff -qr`: Requires `-x` for each pattern or post-processing with grep
- This tool: Built-in support for multiple `-x` patterns in a single command

**Content Comparison:**
- `diff -qr`: Binary comparison, may show "files differ" inconsistently
- This tool: SHA-256 hash comparison, consistent across all file types

**Scripting:**
- `diff -qr`: Output requires parsing mixed formats
- This tool: Structured sections with clear delimiters for easy parsing

### Practical Examples

Compare directories excluding node_modules and .git:

```bash
# Using diff -qr (verbose, harder to parse)
diff -qr -x node_modules -x .git dir1 dir2

# Using this tool (same result, clearer output)
./dircompare.sh -x node_modules/ -x .git/ dir1 dir2
```

### When to Use Each Tool

**Use `diff -qr` when:**
- Quick interactive checks
- Need to see actual file differences (use without `-q`)
- Simple one-off comparisons
- Already familiar with diff output format

**Use this tool when:**
- Writing scripts that process comparison results
- Need multiple directory exclusions
- Want consistent hash-based comparison
- Require structured, parseable output
- Working across different Unix-like systems

### Example Output Comparison

Given directories with differences, `diff -qr` produces:

```
Files dir1/file1.txt and dir2/file1.txt differ
Only in dir1: file2.txt
Only in dir2: file3.txt
```

This tool produces:

```
=== Files only in dir1 ===
file2.txt

=== Files only in dir2 ===
file3.txt

=== Files in both directories with different contents ===
file1.txt
```

The structured format makes it trivial to process each category separately in scripts.
