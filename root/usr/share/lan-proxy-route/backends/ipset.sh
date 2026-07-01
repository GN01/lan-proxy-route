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
		all)
			printf -- '-m set --match-set lpr_proxy_v4 dst'
			;;
		allowlist)
			printf -- '-m set --match-set lpr_clients src -m set --match-set lpr_proxy_v4 dst'
			;;
		blocklist)
			printf -- '-m set --match-set lpr_proxy_v4 dst'
			;;
		*)
			return 1
			;;
	esac
}

lpr_ipset_fake_match() {
	access_mode="$1"
	fake_cidr="$2"

	case "$access_mode" in
		all)
			printf -- '-d %s' "$fake_cidr"
			;;
		allowlist)
			printf -- '-m set --match-set lpr_clients src -d %s' "$fake_cidr"
			;;
		blocklist)
			printf -- '-d %s' "$fake_cidr"
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
ipset create lpr_proxy_v4 hash:net family inet -exist
EOF
}

lpr_ipset_render_mangle() {
	lan_if="$1"
	mark="$2"
	access_mode="$3"
	dns_mode="$4"
	fake_cidr="$5"

	lpr_is_ifname "$lan_if" || return 1
	lpr_is_mark "$mark" || return 1
	lpr_is_cidr "$fake_cidr" || return 1

	case "$access_mode" in
		all|allowlist|blocklist) ;;
		*) return 1 ;;
	esac
	case "$dns_mode" in
		real-ip|fake-ip|mixed) ;;
		*) return 1 ;;
	esac

	client_match="$(lpr_ipset_client_match "$access_mode")" || return 1

	cat <<EOF
iptables -t mangle -N LAN_PROXY_ROUTE
iptables -t mangle -A PREROUTING -i $lan_if -j LAN_PROXY_ROUTE
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_bypass_v4 dst -j RETURN
EOF

	if [ "$access_mode" = "blocklist" ]; then
		cat <<'EOF'
iptables -t mangle -A LAN_PROXY_ROUTE -m set --match-set lpr_blocked_clients src -j RETURN
EOF
	fi

	cat <<EOF
iptables -t mangle -A LAN_PROXY_ROUTE $client_match -j MARK --set-mark $mark
EOF

	if [ "$dns_mode" = "fake-ip" ]; then
		fake_match="$(lpr_ipset_fake_match "$access_mode" "$fake_cidr")" || return 1
		cat <<EOF
iptables -t mangle -A LAN_PROXY_ROUTE $fake_match -j MARK --set-mark $mark
EOF
	fi
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

	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace default via %s dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
}

lpr_ipset_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"
	lan_if="${4:-}"

	lpr_is_mark "$mark" || return 1
	lpr_is_uint "$table" || return 1
	lpr_is_uint "$priority" || return 1
	if [ -n "$lan_if" ]; then
		lpr_is_ifname "$lan_if" || return 1
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
ipset destroy lpr_proxy_v4 2>/dev/null || true
ip rule del fwmark $mark lookup $table priority $priority 2>/dev/null || true
ip route flush table $table 2>/dev/null || true
EOF
}
