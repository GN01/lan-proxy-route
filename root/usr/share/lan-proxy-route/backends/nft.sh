#!/bin/sh

lpr_is_ifname() {
	value="${1:-}"
	case "$value" in
		''|*[!A-Za-z0-9_.:-]*)
			return 1
			;;
	esac
}

lpr_nft_client_prefix() {
	lan_if="$1"
	access_mode="$2"

	lpr_is_ifname "$lan_if" || return 1

	case "$access_mode" in
		all)
			printf 'iifname "%s"' "$lan_if"
			;;
		allowlist)
			printf 'iifname "%s" ip saddr @clients_v4' "$lan_if"
			;;
		blocklist)
			printf 'iifname "%s"' "$lan_if"
			;;
		*)
			return 1
			;;
	esac
}

lpr_nft_render_table() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"
	dns_mode="$4"
	fake_cidr="$5"

	lpr_is_ifname "$lan_if" || return 1
	lpr_is_mark "$mark" || return 1
	case "$access_mode" in
		all|allowlist|blocklist) ;;
		*) return 1 ;;
	esac
	case "$dns_mode" in
		real-ip|fake-ip|mixed) ;;
		*) return 1 ;;
	esac
	lpr_is_cidr "$fake_cidr" || return 1

	prefix="$(lpr_nft_client_prefix "$lan_if" "$access_mode")" || return 1

	cat <<EOF
nft add table inet $LPR_TABLE_NAME
nft add set inet $LPR_TABLE_NAME clients_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME blocked_clients_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME bypass_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME proxy_v4 '{ type ipv4_addr; flags interval; }'
nft add chain inet $LPR_TABLE_NAME prerouting '{ type filter hook prerouting priority mangle; policy accept; }'
nft add rule inet $LPR_TABLE_NAME prerouting iifname "$lan_if" ip daddr @bypass_v4 return
EOF

	if [ "$access_mode" = "blocklist" ]; then
		cat <<EOF
nft add rule inet $LPR_TABLE_NAME prerouting iifname "$lan_if" ip saddr @blocked_clients_v4 return
EOF
	fi

	cat <<EOF
nft add rule inet $LPR_TABLE_NAME prerouting $prefix ip daddr @proxy_v4 meta mark set $mark
EOF

	case "$dns_mode" in
		fake-ip)
			cat <<EOF
nft add rule inet $LPR_TABLE_NAME prerouting $prefix ip daddr $fake_cidr meta mark set $mark
EOF
			;;
	esac
}

lpr_nft_render_elements() {
	set_name="$1"
	shift

	case "$set_name" in
		clients_v4|blocked_clients_v4|bypass_v4|proxy_v4) ;;
		*) return 1 ;;
	esac

	all_cidrs=
	for value in "$@"; do
		[ -n "$value" ] || continue
		entry="$value"
		if ! lpr_is_ipv4 "$entry" && ! lpr_is_cidr "$entry"; then
			return 1
		fi
		if lpr_is_cidr "$entry"; then
			case " $all_cidrs " in
				*" $entry "*) ;;
				*) all_cidrs="$all_cidrs $entry" ;;
			esac
		fi
	done

	rendered_values=
	for value in "$@"; do
		[ -n "$value" ] || continue
		entry="$value"
		case "
$rendered_values
" in
			*"
$entry
"*) continue ;;
		esac
		if lpr_is_ipv4 "$entry"; then
			covered=0
			for cidr in $all_cidrs; do
				if lpr_cidr_contains_ipv4 "$cidr" "$entry"; then
					covered=1
					break
				fi
			done
			[ "$covered" -eq 0 ] || continue
		fi
		if lpr_is_cidr "$entry"; then
			covered=0
			entry_prefix="${entry#*/}"
			for cidr in $all_cidrs; do
				[ "$cidr" != "$entry" ] || continue
				cidr_prefix="${cidr#*/}"
				if [ "$cidr_prefix" -lt "$entry_prefix" ] && lpr_cidr_contains_cidr "$cidr" "$entry"; then
					covered=1
					break
				fi
			done
			[ "$covered" -eq 0 ] || continue
		fi
		rendered_values="${rendered_values}
$entry"
		printf 'nft add element inet %s %s { %s }\n' "$LPR_TABLE_NAME" "$set_name" "$entry"
	done
}

lpr_nft_render_policy_route() {
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

	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace default via %s dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
}

lpr_nft_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"
	x86_ip="${4:-}"
	lan_if="${5:-}"

	lpr_is_mark "$mark" || return 1
	lpr_is_uint "$table" || return 1
	lpr_is_uint "$priority" || return 1
	if [ -n "$x86_ip" ]; then
		lpr_is_ipv4 "$x86_ip" || return 1
	fi
	if [ -n "$lan_if" ]; then
		lpr_is_ifname "$lan_if" || return 1
	fi

	printf 'nft list table inet %s >/dev/null 2>&1 && nft delete table inet %s || true\n' "$LPR_TABLE_NAME" "$LPR_TABLE_NAME"
	printf 'ip rule del fwmark %s lookup %s priority %s 2>/dev/null || true\n' "$mark" "$table" "$priority"
	if [ -n "$x86_ip" ] && [ -n "$lan_if" ]; then
		printf 'ip route del default via %s dev %s table %s 2>/dev/null || true\n' "$x86_ip" "$lan_if" "$table"
	else
		return 1
	fi
}
