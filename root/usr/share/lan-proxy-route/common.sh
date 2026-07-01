#!/bin/sh

LPR_NAME="lan-proxy-route"
LPR_TABLE_NAME="lan_proxy_route"

lpr_log() {
	logger -t "$LPR_NAME" "$*" 2>/dev/null || printf '%s\n' "$*" >&2
}

lpr_die() {
	printf '%s\n' "$*" >&2
	exit 1
}

lpr_is_uint() {
	case "${1:-}" in
		''|*[!0-9]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

lpr_is_ipv4() {
	value="${1:-}"

	case "$value" in
		*.*.*.*.*|.*|*.)
			return 1
			;;
	esac

	octet1=${value%%.*}
	rest=${value#*.}
	[ "$octet1" != "$value" ] || return 1
	octet2=${rest%%.*}
	rest=${rest#*.}
	[ "$rest" != "$octet2" ] || return 1
	octet3=${rest%%.*}
	octet4=${rest#*.}
	[ "$octet4" != "$rest" ] || return 1

	for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
		lpr_is_uint "$octet" || return 1
		[ "$octet" -ge 0 ] 2>/dev/null || return 1
		[ "$octet" -le 255 ] 2>/dev/null || return 1
	done
	return 0
}

lpr_is_cidr() {
	value="${1:-}"
	case "$value" in
		*/*)
			ip="${value%/*}"
			prefix="${value#*/}"
			;;
		*)
			return 1
			;;
	esac

	lpr_is_ipv4 "$ip" || return 1
	lpr_is_uint "$prefix" || return 1
	[ "$prefix" -ge 0 ] 2>/dev/null || return 1
	[ "$prefix" -le 32 ] 2>/dev/null || return 1
	return 0
}

lpr_is_domain() {
	value="${1:-}"
	[ -n "$value" ] || return 1

	case "$value" in
		.*)
			value="${value#.}"
			case "$value" in
				.*)
					return 1
					;;
			esac
			;;
	esac

	case "$value" in
		''|'.'|*' '*|*'/'*|*'*'*|*'?'*|*'..'*|'-'*|*'.-'*|*'-.'*)
			return 1
			;;
	esac

	case "$value" in
		*[!A-Za-z0-9.-]*)
			return 1
			;;
	esac

	case "$value" in
		*.*)
			;;
		*)
			return 1
			;;
	esac

	return 0
}

lpr_is_mark() {
	value="${1:-}"
	case "$value" in
		0x*)
			hex="${value#0x}"
			;;
		0X*)
			hex="${value#0X}"
			;;
		*)
			lpr_is_uint "$value" && return 0
			return 1
			;;
	esac

	[ -n "$hex" ] || return 1
	case "$hex" in
		*[!0-9A-Fa-f]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

lpr_have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

lpr_detect_backend() {
	requested="${1:-auto}"
	case "$requested" in
		nftset|ipset)
			printf '%s\n' "$requested"
			return 0
			;;
		auto)
			if lpr_have_cmd nft && lpr_have_cmd fw4; then
				printf '%s\n' nftset
				return 0
			fi
			if lpr_have_cmd ipset; then
				printf '%s\n' ipset
				return 0
			fi
			return 1
			;;
		*)
			return 1
			;;
	esac
}

lpr_cmd() {
	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		printf '%s\n' "$*"
		return 0
	fi
	"$@"
}
