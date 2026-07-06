#!/bin/sh
set -eu

. ./tests/lib/assert.sh

updater=./root/usr/share/lan-proxy-route/update-chnroute.sh
assert_file_exists "$updater"
sh -n "$updater"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

remote_dir="$tmpdir/remote"
mkdir -p "$remote_dir"
{
	i=1
	while [ "$i" -le 1200 ]; do
		printf '10.%s.%s.0/24\n' "$((i / 256))" "$((i % 256))"
		i=$((i + 1))
	done
} > "$remote_dir/china_ip4.txt"
printf '20990101000000\n' > "$remote_dir/china_ip4.ver"

# Fake fetcher: copies from the local "remote" directory instead of the network.
cat > "$tmpdir/fake-fetch" <<EOF
#!/bin/sh
url="\$1"
dest="\$2"
printf '%s\n' "\$url" >> "$tmpdir/fetch.log"
cp "$remote_dir/\$(basename "\$url")" "\$dest"
EOF
chmod +x "$tmpdir/fake-fetch"

china_file="$tmpdir/china_ip4.txt"
ver_file="$tmpdir/china_ip4.ver"
printf '20000101000000\n' > "$ver_file"
printf '1.0.1.0/24\n' > "$china_file"

# Outdated local version: update replaces list and version.
LPR_FETCH_CMD="$tmpdir/fake-fetch" LPR_CHINA_FILE="$china_file" LPR_CHINA_VER_FILE="$ver_file" \
	LPR_CHNROUTE_URL_BASE="https://example.test/resources" LPR_SKIP_RELOAD=1 \
	sh "$updater" update > "$tmpdir/update.out"
assert_contains "$tmpdir/update.out" "updated to version 20990101000000"
assert_contains "$tmpdir/update.out" "1200 entries"
assert_contains "$ver_file" "20990101000000"
assert_eq 1200 "$(grep -c '/' "$china_file")"
assert_contains "$tmpdir/fetch.log" "https://example.test/resources/china_ip4.ver"
assert_contains "$tmpdir/fetch.log" "https://example.test/resources/china_ip4.txt"

# Same version: no re-download of the list.
: > "$tmpdir/fetch.log"
LPR_FETCH_CMD="$tmpdir/fake-fetch" LPR_CHINA_FILE="$china_file" LPR_CHINA_VER_FILE="$ver_file" \
	LPR_CHNROUTE_URL_BASE="https://example.test/resources" LPR_SKIP_RELOAD=1 \
	sh "$updater" update > "$tmpdir/update-same.out"
assert_contains "$tmpdir/update-same.out" "already up to date"
assert_contains "$tmpdir/fetch.log" "china_ip4.ver"
assert_not_contains "$tmpdir/fetch.log" "china_ip4.txt"

# force-update re-downloads even when versions match.
: > "$tmpdir/fetch.log"
LPR_FETCH_CMD="$tmpdir/fake-fetch" LPR_CHINA_FILE="$china_file" LPR_CHINA_VER_FILE="$ver_file" \
	LPR_CHNROUTE_URL_BASE="https://example.test/resources" LPR_SKIP_RELOAD=1 \
	sh "$updater" force-update > "$tmpdir/update-force.out"
assert_contains "$tmpdir/update-force.out" "updated to version 20990101000000"
assert_contains "$tmpdir/fetch.log" "china_ip4.txt"

# Corrupt download must not replace the local list.
printf 'garbage not cidr\n' > "$remote_dir/china_ip4.txt"
printf '20990202000000\n' > "$remote_dir/china_ip4.ver"
if LPR_FETCH_CMD="$tmpdir/fake-fetch" LPR_CHINA_FILE="$china_file" LPR_CHINA_VER_FILE="$ver_file" \
	LPR_CHNROUTE_URL_BASE="https://example.test/resources" LPR_SKIP_RELOAD=1 \
	sh "$updater" update > "$tmpdir/update-bad.out" 2>&1; then
	fail "corrupt download accepted"
fi
assert_contains "$ver_file" "20990101000000"
assert_eq 1200 "$(grep -c '/' "$china_file")"

# Too-few-entries download must be rejected as well.
printf '1.0.1.0/24\n' > "$remote_dir/china_ip4.txt"
if LPR_FETCH_CMD="$tmpdir/fake-fetch" LPR_CHINA_FILE="$china_file" LPR_CHINA_VER_FILE="$ver_file" \
	LPR_CHNROUTE_URL_BASE="https://example.test/resources" LPR_SKIP_RELOAD=1 \
	sh "$updater" update > "$tmpdir/update-few.out" 2>&1; then
	fail "too-small download accepted"
fi
assert_eq 1200 "$(grep -c '/' "$china_file")"

# version command reports the local version.
version_out="$(LPR_CHINA_VER_FILE="$ver_file" sh "$updater" version)"
assert_eq 20990101000000 "$version_out"
