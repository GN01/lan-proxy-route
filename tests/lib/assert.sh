#!/bin/sh

fail() {
	printf 'not ok - %s\n' "$*" >&2
	exit 1
}

assert_file_exists() {
	[ -f "$1" ] || fail "missing file: $1"
}

assert_executable() {
	[ -x "$1" ] || fail "not executable: $1"
}

assert_contains() {
	file="$1"
	pattern="$2"
	grep -F "$pattern" "$file" >/dev/null 2>&1 || fail "$file does not contain: $pattern"
}

assert_not_contains() {
	file="$1"
	pattern="$2"
	if grep -F "$pattern" "$file" >/dev/null 2>&1; then
		fail "$file unexpectedly contains: $pattern"
	fi
}

assert_eq() {
	expected="$1"
	actual="$2"
	[ "$expected" = "$actual" ] || fail "expected [$expected], got [$actual]"
}
