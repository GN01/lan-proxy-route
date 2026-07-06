#!/bin/sh

lpr_is_ifname() {
	value="${1:-}"
	case "$value" in
		''|*[!A-Za-z0-9_.:-]*)
			return 1
			;;
	esac
}

lpr_ipset_client_match() {
	access_mode="$1"

	case "$access_mode" in
		all|blocklist)
			printf ''
			;;
		allowlist)
			printf -- '-m set --match-set lpr_clients src '
			;;
		*)
			return 1
			;;
	esac
}

lpr_ipset_render_setup() {
	cat <<'EOF'
ipset create lpr_clients hash:net family inet -exist
ipset create lpr_blocked_clients hash:net family inet -exist
ipset create lpr_bypass_v4 hash:net family inet -exist
ipset create lpr_china_v4 hash:net family inet maxelem 65536 -exist
EOF
}

lpr_ipset_render_elements() {
	set_name="$1"
	shift

	case "$set_name" in
		lpr_clients|lpr_blocked_clients|lpr_bypass_v4|lpr_china_v4) ;;
		*) return 1 ;;
	esac

	for value in "$@"; do
		[ -n "$value" ] || continue
		entry="$value"
		if ! lpr_is_ipv4 "$entry" && ! lpr_is_cidr "$entry"; then
			return 1
		fi
		printf 'ipset add %s %s -exist\n' "$set_name" "$entry"
	done
}

# Bulk-load a large CIDR list file into a set via `ipset restore`, batched
# into chunks piped through a single ipset invocation per chunk.
lpr_ipset_render_file_elements() {
	set_name="$1"
	file="$2"
	chunk_size="${3:-500}"

	case "$set_name" in
		lpr_bypass_v4|lpr_china_v4) ;;
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
			chunk="add $set_name $line -exist"
		else
			chunk="$chunk\nadd $set_name $line -exist"
		fi
		count=$((count + 1))
		if [ "$count" -ge "$chunk_size" ]; then
			printf 'printf '\''%s\\n'\'' | ipset restore\n' "$chunk"
			chunk=
			count=0
		fi
	done < "$file"
	if [ -n "$chunk" ]; then
		printf 'printf '\''%s\\n'\'' | ipset restore\n' "$chunk"
	fi
}

# GeoIP split model: bypass and China destinations RETURN; everything else
# from eligible clients is marked for the proxy routing table.
lpr_ipset_render_mangle() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"

	lpr_is_ifname "$lan_if" || return 1
	lpr_is_mark "$mark" || return 1

	case "$access_mode" in
		all|allowlist|blocklist) ;;
		*) return 1 ;;
	esac

	client_match="$(lpr_ipset_client_match "$access_mode")" || return 1

	cat <<EOF
iptables -t mangle -N LAN_PROXY_ROUTE
iptables -t mangle -A PREROUTING -i $lan_if -j LAN_PROXY_ROUTE
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_china_v4 dst -j RETURN
EOF

	if [ "$access_mode" = "blocklist" ]; then
		cat <<'EOF'
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN
EOF
	fi

	cat <<EOF
iptables -t mangle -A LAN_PROXY_ROUTE ${client_match}-j MARK --set-mark $mark
EOF
}

lpr_ipset_render_policy_route() {
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

lpr_ipset_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"
	lan_if="${4:-}"
	x86_ip="${5:-}"

	lpr_is_mark "$mark" || return 1
	lpr_is_uint "$table" || return 1
	lpr_is_uint "$priority" || return 1
	if [ -n "$lan_if" ]; then
		lpr_is_ifname "$lan_if" || return 1
	fi
	if [ -n "$x86_ip" ]; then
		lpr_is_ipv4 "$x86_ip" || return 1
	fi

	if [ -n "$lan_if" ]; then
		printf 'iptables -t mangle -D PREROUTING -i %s -j LAN_PROXY_ROUTE 2>/dev/null || true\n' "$lan_if"
	else
		printf 'iptables -t mangle -D PREROUTING -j LAN_PROXY_ROUTE 2>/dev/null || true\n'
	fi
	cat <<EOF
iptables -t mangle -F LAN_PROXY_ROUTE 2>/dev/null || true
iptables -t mangle -X LAN_PROXY_ROUTE 2>/dev/null || true
ipset destroy lpr_clients 2>/dev/null || true
ipset destroy lpr_blocked_clients 2>/dev/null || true
ipset destroy lpr_bypass_v4 2>/dev/null || true
ipset destroy lpr_china_v4 2>/dev/null || true
ip rule del fwmark $mark lookup $table priority $priority 2>/dev/null || true
EOF
	if [ -n "$x86_ip" ] && [ -n "$lan_if" ]; then
		lpr_render_policy_route_cleanup "$table" "$x86_ip" "$lan_if"
	else
		return 1
	fi
}
