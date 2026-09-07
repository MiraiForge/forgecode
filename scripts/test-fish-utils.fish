#!/usr/bin/env fish

# Correctness and performance tests for `forge fish format`, which wraps bare
# file paths in @[...] syntax. All parsing logic lives in Rust; these tests
# exercise the CLI subcommand end-to-end from fish.
#
# Usage: fish scripts/test-fish-utils.fish

set -l script_dir (dirname (status filename))

# Resolve the forge binary (prefer local debug build)
set -g __forge_test_bin $script_dir/../target/debug/forge
if set -q FORGE_BIN; and test -n "$FORGE_BIN"
    set -g __forge_test_bin $FORGE_BIN
end

if not test -x $__forge_test_bin
    echo (set_color red)"forge binary not found at $__forge_test_bin"(set_color normal)
    echo "Run: cargo build -p forge_main"
    exit 1
end

# Wrapper that calls the Rust formatter
function format
    command $__forge_test_bin fish format --buffer $argv[1] </dev/null
end

# Temporary files for paths with spaces
set -l tmpdir_test (mktemp -d)
mkdir -p "$tmpdir_test/my folder"
touch "$tmpdir_test/my folder/test file.txt"
touch "$tmpdir_test/simple.txt"

# --- Test harness -----------------------------------------------------------

set -g __pass 0
set -g __fail 0

# assert_eq <test name> <actual> <expected>
function assert_eq
    set -l test_name $argv[1]
    set -l actual $argv[2]
    set -l expected $argv[3]

    if test "$actual" = "$expected"
        printf '  %s✓%s %s\n' (set_color green) (set_color normal) $test_name
        set -g __pass (math $__pass + 1)
    else
        printf '  %s✗%s %s\n' (set_color red) (set_color normal) $test_name
        printf '    %sexpected:%s %s\n' (set_color brblack) (set_color normal) "$expected"
        printf '    %s  actual:%s %s\n' (set_color brblack) (set_color normal) "$actual"
        set -g __fail (math $__fail + 1)
    end
end

# --- Correctness tests ------------------------------------------------------

echo
echo (set_color --bold)"Correctness Tests"(set_color normal)" "(set_color brblack)"— forge fish format"(set_color normal)
echo

# Basic wrapping
assert_eq "bare existing path" \
    (format "/usr/bin/env") \
    "@[/usr/bin/env]"

assert_eq "path in sentence" \
    (format "look at /usr/bin/env please") \
    "look at @[/usr/bin/env] please"

# Non-existent paths left untouched
assert_eq "nonexistent path untouched" \
    (format "check /nonexistent/foo.rs") \
    "check /nonexistent/foo.rs"

# Already wrapped left untouched
assert_eq "already wrapped @[...] untouched" \
    (format "check @[/usr/bin/env] ok") \
    "check @[/usr/bin/env] ok"

# Plain text (no paths)
assert_eq "plain text no paths" \
    (format "hello world") \
    "hello world"

# Paths with spaces
assert_eq "bare path with spaces" \
    (format "$tmpdir_test/my folder/test file.txt") \
    "@[$tmpdir_test/my folder/test file.txt]"

# Quoted paths with spaces
assert_eq "single-quoted path with spaces" \
    (format "'$tmpdir_test/my folder/test file.txt'") \
    "@[$tmpdir_test/my folder/test file.txt]"

assert_eq "double-quoted path with spaces" \
    (format "\"$tmpdir_test/my folder/test file.txt\"") \
    "@[$tmpdir_test/my folder/test file.txt]"

assert_eq "single-quoted path with spaces in sentence" \
    (format "check '$tmpdir_test/my folder/test file.txt' please") \
    "check @[$tmpdir_test/my folder/test file.txt] please"

# Simple path (no spaces)
assert_eq "simple path no spaces" \
    (format "$tmpdir_test/simple.txt") \
    "@[$tmpdir_test/simple.txt]"

# Multiple paths
assert_eq "multiple existing paths" \
    (format "compare /usr/bin/env and $tmpdir_test/simple.txt") \
    "compare @[/usr/bin/env] and @[$tmpdir_test/simple.txt]"

assert_eq "mixed existing and nonexistent" \
    (format "check /usr/bin/env and /nonexistent/foo.rs") \
    "check @[/usr/bin/env] and /nonexistent/foo.rs"

# Empty input
assert_eq "empty input" \
    (format '') \
    ""

# Backslash-escaped paths (terminals like Ghostty send /path/my\ file.txt)
set -l escaped_path "$tmpdir_test/my\\ folder/test\\ file.txt"
assert_eq "backslash-escaped path (whole paste)" \
    (format "$escaped_path") \
    "@[$tmpdir_test/my folder/test file.txt]"

assert_eq "backslash-escaped path in sentence" \
    (format "check $escaped_path please") \
    "check @[$tmpdir_test/my folder/test file.txt] please"

assert_eq "path without spaces (no escaping needed)" \
    (format "$tmpdir_test/simple.txt") \
    "@[$tmpdir_test/simple.txt]"

assert_eq "backslash-escaped nonexistent path untouched" \
    (format "/nonexistent/my\\ folder/file.txt") \
    "/nonexistent/my\\ folder/file.txt"

# --- Performance tests -------------------------------------------------------

echo
echo (set_color --bold)"Performance Tests"(set_color normal)" "(set_color brblack)"— forge fish format"(set_color normal)
echo

set -l iterations 10

# bench <label> <buffer>
function bench
    set -l label $argv[1]
    set -l buffer $argv[2]
    set -l iterations $argv[3]
    set -l start (perl -MTime::HiRes=time -e 'printf "%.3f", time')
    for i in (seq 1 $iterations)
        format $buffer >/dev/null
    end
    set -l end (perl -MTime::HiRes=time -e 'printf "%.3f", time')
    set -l avg (math "($end - $start) * 1000 / $iterations")
    printf '  %s%-19s%s %s%.2f%s %sms avg (%d iterations)%s\n' (set_color brblack) $label (set_color normal) (set_color cyan) $avg (set_color normal) (set_color brblack) $iterations (set_color normal)
end

bench "simple path" "look at /usr/bin/env please" $iterations
bench "quoted path spaces" "check '$tmpdir_test/my folder/test file.txt' please" $iterations
bench "plain text" "explain how this works in detail" $iterations
bench "already wrapped" "check @[/usr/bin/env] and explain" $iterations

# --- Cleanup -----------------------------------------------------------------

rm -rf "$tmpdir_test"

# --- Summary -----------------------------------------------------------------

echo
if test $__fail -eq 0
    echo (set_color green)"✓ $__pass passed"(set_color normal)
    exit 0
else
    echo (set_color red)"✗ $__fail failed"(set_color normal)", $__pass passed"
    exit 1
end
