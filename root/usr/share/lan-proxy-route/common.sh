#!/bin/sh

LPR_NAME="lan-proxy-route"
LPR_TABLE_NAME="lan_proxy_route"

lpr_log() {
	logger -t "$LPR_NAME" "$*" 2>/dev/null || printf '%s\n' "$*" >&2
}

lpr_die() {
	lpr_log "error: $*"
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

lpr_ipv4_to_int() {
	value="${1:-}"
	lpr_is_ipv4 "$value" || return 1

	octet1=${value%%.*}
	rest=${value#*.}
	octet2=${rest%%.*}
	rest=${rest#*.}
	octet3=${rest%%.*}
	octet4=${rest#*.}

	printf '%s\n' "$((octet1 * 16777216 + octet2 * 65536 + octet3 * 256 + octet4))"
}

lpr_cidr_contains_ipv4() {
	cidr="${1:-}"
	host_ip="${2:-}"
	lpr_is_cidr "$cidr" || return 1
	lpr_is_ipv4 "$host_ip" || return 1

	network="${cidr%/*}"
	prefix="${cidr#*/}"
	network_int="$(lpr_ipv4_to_int "$network")" || return 1
	ip_int="$(lpr_ipv4_to_int "$host_ip")" || return 1

	if [ "$prefix" -eq 0 ]; then
		mask=0
	else
		mask="$((4294967295 - ((1 << (32 - prefix)) - 1)))"
	fi

	[ "$((ip_int & mask))" -eq "$((network_int & mask))" ]
}

lpr_cidr_contains_cidr() {
	parent_cidr="${1:-}"
	child_cidr="${2:-}"
	lpr_is_cidr "$parent_cidr" || return 1
	lpr_is_cidr "$child_cidr" || return 1

	parent_prefix="${parent_cidr#*/}"
	child_prefix="${child_cidr#*/}"
	[ "$parent_prefix" -le "$child_prefix" ] || return 1
	lpr_cidr_contains_ipv4 "$parent_cidr" "${child_cidr%/*}"
}

lpr_is_domain() {
	value="${1:-}"
	[ -n "$value" ] || return 1

	case "$value" in
		.*)
			value="${value#.}"
			;;
	esac

	case "$value" in
		''|'.'|*'.'|*' '*|*'/'*|*'*'*|*'?'*|*'..'*)
			return 1
			;;
	esac

	has_dot=0
	while :; do
		label="${value%%.*}"
		rest="${value#*.}"

		[ -n "$label" ] || return 1
		case "$label" in
			-*|*-) return 1 ;;
			*[!A-Za-z0-9-]*) return 1 ;;
		esac

		if [ "$rest" = "$value" ]; then
			[ "$has_dot" -eq 1 ] || return 1
			return 0
		fi

		has_dot=1
		value="$rest"
	done
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

lpr_trim_line() {
	printf '%s' "${1:-}" | sed 's/^[	 ]*//; s/[	 ]*$//'
}

lpr_strip_quotes() {
	value="$(lpr_trim_line "${1:-}")"
	case "$value" in
		\'*\')
			value="${value#\'}"
			value="${value%\'}"
			;;
		\"*\")
			value="${value#\"}"
			value="${value%\"}"
			;;
	esac
	printf '%s\n' "$value"
}

lpr_is_bool_flag() {
	case "${1:-}" in
		0|1) return 0 ;;
		*) return 1 ;;
	esac
}

lpr_dns_server_ip() {
	value="${1:-}"
	value="${value%%#*}"
	printf '%s\n' "$value"
}

lpr_is_dns_server() {
	ip="$(lpr_dns_server_ip "${1:-}")"
	lpr_is_ipv4 "$ip" || return 1
	case "${1:-}" in
		*#*)
			port="${1#*#}"
			lpr_is_uint "$port" || return 1
			[ "$port" -ge 1 ] 2>/dev/null || return 1
			[ "$port" -le 65535 ] 2>/dev/null || return 1
			;;
	esac
	return 0
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

lpr_render_policy_route() {
	mark="$1"
	table="$2"
	priority="$3"
	x86_ip="$4"
	lan_if="$5"

	lpr_is_mark "$mark" || return 1
	lpr_is_uint "$table" || return 1
	lpr_is_uint "$priority" || return 1
	lpr_is_ipv4 "$x86_ip" || return 1
	lpr_is_ifname "$lan_if" || return 1

	# LAN-side proxy hosts are on-link; without `onlink` iproute2 rejects the gateway.
	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace %s/32 dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
	printf 'ip route replace default via %s dev %s table %s onlink\n' "$x86_ip" "$lan_if" "$table"
}

lpr_render_policy_route_cleanup() {
	table="$1"
	x86_ip="$2"
	lan_if="$3"

	lpr_is_uint "$table" || return 1
	lpr_is_ipv4 "$x86_ip" || return 1
	lpr_is_ifname "$lan_if" || return 1

	printf 'ip route del default via %s dev %s table %s 2>/dev/null || true\n' "$x86_ip" "$lan_if" "$table"
	printf 'ip route del %s/32 dev %s table %s 2>/dev/null || true\n' "$x86_ip" "$lan_if" "$table"
}

lpr_cmd() {
	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		printf '%s\n' "$*"
		return 0
	fi
	"$@"
}
