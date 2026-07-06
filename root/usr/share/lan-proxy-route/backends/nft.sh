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

# GeoIP split model (homeproxy-style bypass_cn): reserved/custom bypass and
# china_v4 destinations stay on the main routing path (no fwmark); only
# foreign destinations are marked for the proxy routing table.
lpr_nft_render_table() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"

	lpr_is_ifname "$lan_if" || return 1
	lpr_is_mark "$mark" || return 1
	case "$access_mode" in
		all|allowlist|blocklist) ;;
		*) return 1 ;;
	esac

	prefix="$(lpr_nft_client_prefix "$lan_if" "$access_mode")" || return 1

	cat <<EOF
nft add table inet $LPR_TABLE_NAME
nft add set inet $LPR_TABLE_NAME clients_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME blocked_clients_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME bypass_v4 '{ type ipv4_addr; flags interval; }'
nft add set inet $LPR_TABLE_NAME china_v4 '{ type ipv4_addr; flags interval; }'
nft add chain inet $LPR_TABLE_NAME prerouting '{ type filter hook prerouting priority mangle; policy accept; }'
EOF

	if [ "$access_mode" = "blocklist" ]; then
		cat <<EOF
nft add rule inet $LPR_TABLE_NAME prerouting iifname "$lan_if" ip saddr @blocked_clients_v4 return
EOF
	fi

	cat <<EOF
nft add rule inet $LPR_TABLE_NAME prerouting iifname "$lan_if" ip daddr @bypass_v4 return
nft add rule inet $LPR_TABLE_NAME prerouting iifname "$lan_if" ip daddr @china_v4 return
nft add rule inet $LPR_TABLE_NAME prerouting $prefix meta mark set $mark
EOF
}

lpr_nft_render_elements() {
	set_name="$1"
	shift

	case "$set_name" in
		clients_v4|blocked_clients_v4|bypass_v4|china_v4) ;;
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

# User-defined bypass entries are always loaded as-is (only skip exact
# duplicates). Subnet dedup is intentionally disabled so explicit host IPs
# remain visible and are not dropped when covered by a broader bypass CIDR.
lpr_nft_render_bypass_elements() {
	set_name="$1"
	shift

	[ "$set_name" = "bypass_v4" ] || return 1

	rendered_values=
	for value in "$@"; do
		[ -n "$value" ] || continue
		entry="$value"
		if ! lpr_is_ipv4 "$entry" && ! lpr_is_cidr "$entry"; then
			return 1
		fi
		case "
$rendered_values
" in
			*"
$entry
"*) continue ;;
		esac
		rendered_values="${rendered_values}
$entry"
		printf 'nft add element inet %s %s { %s }\n' "$LPR_TABLE_NAME" "$set_name" "$entry"
	done
}

# Bulk-load a large CIDR list file into a set. Entries are batched into
# chunks so thousands of CIDRs do not need one nft invocation each.
lpr_nft_render_file_elements() {
	set_name="$1"
	file="$2"
	chunk_size="${3:-500}"

	case "$set_name" in
		bypass_v4|china_v4) ;;
		*) return 1 ;;
	esac
	[ -f "$file" ] || return 1
	lpr_is_uint "$chunk_size" || return 1
	[ "$chunk_size" -ge 1 ] || return 1

	chunk=
	count=0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|\#*) continue ;;
		esac
		if ! lpr_is_cidr "$line" && ! lpr_is_ipv4 "$line"; then
			continue
		fi
		if [ -z "$chunk" ]; then
			chunk="$line"
		else
			chunk="$chunk, $line"
		fi
		count=$((count + 1))
		if [ "$count" -ge "$chunk_size" ]; then
			printf 'nft add element inet %s %s { %s }\n' "$LPR_TABLE_NAME" "$set_name" "$chunk"
			chunk=
			count=0
		fi
	done < "$file"
	if [ -n "$chunk" ]; then
		printf 'nft add element inet %s %s { %s }\n' "$LPR_TABLE_NAME" "$set_name" "$chunk"
	fi
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

	lpr_render_policy_route "$mark" "$table" "$priority" "$x86_ip" "$lan_if"
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
		lpr_render_policy_route_cleanup "$table" "$x86_ip" "$lan_if"
	else
		return 1
	fi
}
