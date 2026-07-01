#!/bin/sh

lpr_nft_client_prefix() {
	lan_if="$1"
	access_mode="$2"

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

	prefix="$(lpr_nft_client_prefix "$lan_if" "$access_mode")" || return 1

	cat <<EOF
table inet lan_proxy_route {
	set clients_v4 {
		type ipv4_addr
		flags interval
	}

	set blocked_clients_v4 {
		type ipv4_addr
		flags interval
	}

	set bypass_v4 {
		type ipv4_addr
		flags interval
	}

	set proxy_v4 {
		type ipv4_addr
		flags interval
	}

	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname "$lan_if" ip daddr @bypass_v4 return
EOF

	if [ "$access_mode" = "blocklist" ]; then
		cat <<EOF
		iifname "$lan_if" ip saddr @blocked_clients_v4 return
EOF
	fi

	cat <<EOF
		$prefix ip daddr @proxy_v4 meta mark set $mark
EOF

	case "$dns_mode" in
		fake-ip)
			cat <<EOF
		$prefix ip daddr $fake_cidr meta mark set $mark
EOF
			;;
	esac

	cat <<EOF
	}
}
EOF
}

lpr_nft_render_policy_route() {
	mark="$1"
	table="$2"
	priority="$3"
	x86_ip="$4"
	lan_if="$5"

	printf 'ip rule add fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route replace default via %s dev %s table %s\n' "$x86_ip" "$lan_if" "$table"
}

lpr_nft_render_cleanup() {
	mark="$1"
	table="$2"
	priority="$3"

	printf 'nft delete table inet lan_proxy_route\n'
	printf 'ip rule del fwmark %s lookup %s priority %s\n' "$mark" "$table" "$priority"
	printf 'ip route flush table %s\n' "$table"
}
