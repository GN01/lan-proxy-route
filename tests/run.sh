#!/bin/sh
set -eu

for test_script in tests/static/*.sh tests/unit/*.sh; do
	[ -f "$test_script" ] || continue
	printf '==> %s\n' "$test_script"
	sh "$test_script"
done
