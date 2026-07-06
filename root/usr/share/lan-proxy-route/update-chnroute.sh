#!/bin/sh
# Update the bundled China IPv4 list from the homeproxy resources repo.
set -eu

BASE_DIR="${LPR_BASE_DIR:-/usr/share/lan-proxy-route}"
if [ -f "./root/usr/share/lan-proxy-route/common.sh" ]; then
	BASE_DIR="./root/usr/share/lan-proxy-route"
fi

. "$BASE_DIR/common.sh"

LPR_ETC_DIR="${LPR_ETC_DIR:-/etc/lan-proxy-route}"
if [ -d "./root/etc/lan-proxy-route" ]; then
	LPR_ETC_DIR="./root/etc/lan-proxy-route"
fi

LPR_CHINA_FILE="${LPR_CHINA_FILE:-$LPR_ETC_DIR/china_ip4.txt}"
LPR_CHINA_VER_FILE="${LPR_CHINA_VER_FILE:-$LPR_ETC_DIR/china_ip4.ver}"
LPR_CHNROUTE_MIN_ENTRIES="${LPR_CHNROUTE_MIN_ENTRIES:-1000}"
LPR_INIT_SCRIPT="${LPR_INIT_SCRIPT:-/etc/init.d/lan-proxy-route}"

lpr_chnroute_url_base() {
	if [ -n "${LPR_CHNROUTE_URL_BASE:-}" ]; then
		printf '%s\n' "$LPR_CHNROUTE_URL_BASE"
		return 0
	fi
	if command -v uci >/dev/null 2>&1; then
		configured="$(uci -q get lan_proxy_route.global.chnroute_url 2>/dev/null || true)"
		if [ -n "$configured" ]; then
			printf '%s\n' "$configured"
			return 0
		fi
	fi
	printf '%s\n' "https://raw.githubusercontent.com/immortalwrt/homeproxy/master/root/etc/homeproxy/resources"
}

lpr_fetch() {
	url="$1"
	dest="$2"
	if [ -n "${LPR_FETCH_CMD:-}" ]; then
		"$LPR_FETCH_CMD" "$url" "$dest"
		return $?
	fi
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 10 -o "$dest" "$url"
		return $?
	fi
	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -T 10 -O "$dest" "$url"
		return $?
	fi
	if command -v wget >/dev/null 2>&1; then
		wget -q -T 10 -O "$dest" "$url"
		return $?
	fi
	lpr_die "no download tool available (curl/uclient-fetch/wget)"
}

lpr_chnroute_validate_file() {
	file="$1"
	entries=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|\#*) continue ;;
		esac
		if ! lpr_is_cidr "$line" && ! lpr_is_ipv4 "$line"; then
			lpr_log "chnroute: invalid entry in download: $line"
			return 1
		fi
		entries=$((entries + 1))
	done < "$file"
	if [ "$entries" -lt "$LPR_CHNROUTE_MIN_ENTRIES" ]; then
		lpr_log "chnroute: too few entries in download: $entries"
		return 1
	fi
	printf '%s\n' "$entries"
}

lpr_chnroute_update() {
	force="${1:-0}"
	base_url="$(lpr_chnroute_url_base)"
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT INT TERM

	if ! lpr_fetch "$base_url/china_ip4.ver" "$tmpdir/china_ip4.ver"; then
		lpr_die "chnroute: failed to fetch version from $base_url"
	fi
	remote_ver="$(head -n 1 "$tmpdir/china_ip4.ver" | tr -cd '0-9')"
	[ -n "$remote_ver" ] || lpr_die "chnroute: empty remote version"

	local_ver=""
	if [ -f "$LPR_CHINA_VER_FILE" ]; then
		local_ver="$(head -n 1 "$LPR_CHINA_VER_FILE" | tr -cd '0-9')"
	fi

	if [ "$force" != "1" ] && [ -n "$local_ver" ] && [ "$remote_ver" = "$local_ver" ]; then
		printf 'chnroute: already up to date (version %s)\n' "$local_ver"
		return 0
	fi

	if ! lpr_fetch "$base_url/china_ip4.txt" "$tmpdir/china_ip4.txt"; then
		lpr_die "chnroute: failed to fetch list from $base_url"
	fi

	entries="$(lpr_chnroute_validate_file "$tmpdir/china_ip4.txt")" || \
		lpr_die "chnroute: downloaded list failed validation"

	mkdir -p "$(dirname "$LPR_CHINA_FILE")"
	mv "$tmpdir/china_ip4.txt" "$LPR_CHINA_FILE"
	printf '%s\n' "$remote_ver" > "$LPR_CHINA_VER_FILE"
	lpr_log "chnroute: updated to version $remote_ver ($entries entries)"
	printf 'chnroute: updated to version %s (%s entries)\n' "$remote_ver" "$entries"

	if [ "${LPR_SKIP_RELOAD:-0}" != "1" ] && [ -x "$LPR_INIT_SCRIPT" ]; then
		"$LPR_INIT_SCRIPT" reload >/dev/null 2>&1 || true
	fi
}

case "${1:-update}" in
	update)
		lpr_chnroute_update 0
		;;
	force-update)
		lpr_chnroute_update 1
		;;
	version)
		if [ -f "$LPR_CHINA_VER_FILE" ]; then
			head -n 1 "$LPR_CHINA_VER_FILE"
		else
			printf 'unknown\n'
		fi
		;;
	*)
		lpr_die "usage: $0 update|force-update|version"
		;;
esac
