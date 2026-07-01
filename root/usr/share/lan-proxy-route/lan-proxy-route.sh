#!/bin/sh
set -eu

BASE_DIR="${LPR_BASE_DIR:-/usr/share/lan-proxy-route}"
if [ -f "./root/usr/share/lan-proxy-route/common.sh" ]; then
	BASE_DIR="./root/usr/share/lan-proxy-route"
fi

. "$BASE_DIR/common.sh"
. "$BASE_DIR/dnsmasq.sh"
. "$BASE_DIR/backends/nft.sh"
. "$BASE_DIR/backends/ipset.sh"

LPR_BACKEND="${LPR_BACKEND:-auto}"
LPR_DNS_MODE="${LPR_DNS_MODE:-real-ip}"
LPR_MARK="${LPR_MARK:-0x210}"
LPR_TABLE="${LPR_TABLE:-210}"
LPR_PRIORITY="${LPR_PRIORITY:-10210}"
LPR_LAN_IF="${LPR_LAN_IF:-br-lan}"
LPR_X86_IP="${LPR_X86_IP:-192.168.1.2}"
LPR_PROXY_DNS="${LPR_PROXY_DNS:-192.168.1.2#53}"
LPR_FAKE_CIDR="${LPR_FAKE_CIDR:-198.18.0.0/15}"
LPR_ACCESS_MODE="${LPR_ACCESS_MODE:-all}"
LPR_HIJACK_53="${LPR_HIJACK_53:-1}"
LPR_BLOCK_DOT="${LPR_BLOCK_DOT:-1}"
LPR_ROUTER_IP="${LPR_ROUTER_IP:-192.168.1.1}"
LPR_DNSMASQ_CONF="${LPR_DNSMASQ_CONF:-/tmp/dnsmasq.d/lan-proxy-route.conf}"
LPR_ETC_DIR="${LPR_ETC_DIR:-/etc/lan-proxy-route}"
if [ -d "./root/etc/lan-proxy-route" ]; then
	LPR_ETC_DIR="./root/etc/lan-proxy-route"
fi

lpr_service_backend() {
	lpr_detect_backend "$LPR_BACKEND" || lpr_die "unable to detect backend"
}

lpr_service_validate() {
	lpr_is_ipv4 "$LPR_X86_IP" || lpr_die "invalid proxy IP: $LPR_X86_IP"
	lpr_is_mark "$LPR_MARK" || lpr_die "invalid mark: $LPR_MARK"
	lpr_is_uint "$LPR_TABLE" || lpr_die "invalid table: $LPR_TABLE"
	lpr_is_uint "$LPR_PRIORITY" || lpr_die "invalid priority: $LPR_PRIORITY"
	lpr_is_ifname "$LPR_LAN_IF" || lpr_die "invalid LAN interface: $LPR_LAN_IF"
	lpr_is_cidr "$LPR_FAKE_CIDR" || lpr_die "invalid fake IP CIDR: $LPR_FAKE_CIDR"
	lpr_is_ipv4 "${LPR_PROXY_DNS%%#*}" || lpr_die "invalid proxy DNS: $LPR_PROXY_DNS"
	lpr_is_ipv4 "$LPR_ROUTER_IP" || lpr_die "invalid router IP: $LPR_ROUTER_IP"

	case "$LPR_DNS_MODE" in
		real-ip|fake-ip|mixed) ;;
		*) lpr_die "invalid DNS mode: $LPR_DNS_MODE" ;;
	esac
	case "$LPR_ACCESS_MODE" in
		all|allowlist|blocklist) ;;
		*) lpr_die "invalid access mode: $LPR_ACCESS_MODE" ;;
	esac
	case "$LPR_HIJACK_53" in
		0|1) ;;
		*) lpr_die "invalid hijack_53 flag: $LPR_HIJACK_53" ;;
	esac
	case "$LPR_BLOCK_DOT" in
		0|1) ;;
		*) lpr_die "invalid block_dot flag: $LPR_BLOCK_DOT" ;;
	esac

	lpr_service_backend >/dev/null
}

lpr_service_render_backend() {
	backend="$1"

	case "$backend" in
		nftset)
			lpr_nft_render_table "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$LPR_DNS_MODE" "$LPR_FAKE_CIDR"
			lpr_nft_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
		ipset)
			lpr_ipset_render_setup
			lpr_ipset_render_mangle "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$LPR_DNS_MODE" "$LPR_FAKE_CIDR"
			lpr_ipset_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
	esac
}

lpr_service_render_dns() {
	backend="$1"

	lpr_dnsmasq_render_config "$backend" "114.114.114.114,223.5.5.5" "$LPR_PROXY_DNS" \
		"$LPR_ETC_DIR/adblock.txt:adblock:real-ip" \
		"$LPR_ETC_DIR/gfwlist.txt:proxy:$LPR_DNS_MODE" \
		"$LPR_ETC_DIR/custom-proxy-domains.txt:proxy:$LPR_DNS_MODE" \
		"$LPR_ETC_DIR/custom-bypass-domains.txt:bypass:real-ip"
	lpr_dns_render_firewall "$backend" "$LPR_LAN_IF" "$LPR_ROUTER_IP" "$LPR_HIJACK_53" "$LPR_BLOCK_DOT"
}

lpr_service_render_dnsmasq_config() {
	backend="$1"

	lpr_dnsmasq_render_config "$backend" "114.114.114.114,223.5.5.5" "$LPR_PROXY_DNS" \
		"$LPR_ETC_DIR/adblock.txt:adblock:real-ip" \
		"$LPR_ETC_DIR/gfwlist.txt:proxy:$LPR_DNS_MODE" \
		"$LPR_ETC_DIR/custom-proxy-domains.txt:proxy:$LPR_DNS_MODE" \
		"$LPR_ETC_DIR/custom-bypass-domains.txt:bypass:real-ip"
}

lpr_service_render_dns_firewall() {
	backend="$1"
	lpr_dns_render_firewall "$backend" "$LPR_LAN_IF" "$LPR_ROUTER_IP" "$LPR_HIJACK_53" "$LPR_BLOCK_DOT"
}

lpr_service_render() {
	backend="$(lpr_service_backend)"
	lpr_service_render_backend "$backend"
	lpr_service_render_dnsmasq_config "$backend"
	lpr_service_render_dns_firewall "$backend"
}

lpr_service_run_commands() {
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		case "$line" in
			\#*) continue ;;
		esac

		if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
			printf '%s\n' "$line"
		else
			if [ -n "${LPR_COMMAND_RUNNER:-}" ]; then
				"$LPR_COMMAND_RUNNER" "$line"
			else
				sh -c "$line"
			fi
		fi
	done
}

lpr_service_write_dnsmasq_config() {
	backend="$1"
	conf_dir="$(dirname "$LPR_DNSMASQ_CONF")"
	[ -d "$conf_dir" ] || mkdir -p "$conf_dir"
	lpr_service_render_dnsmasq_config "$backend" > "$LPR_DNSMASQ_CONF"
}

lpr_service_render_cleanup() {
	backend="$1"

	case "$backend" in
		nftset)
			cat <<EOF
nft flush chain inet $LPR_TABLE_NAME dns_hijack 2>/dev/null || true
nft delete chain inet $LPR_TABLE_NAME dns_hijack 2>/dev/null || true
nft flush chain inet $LPR_TABLE_NAME dns_dot_block 2>/dev/null || true
nft delete chain inet $LPR_TABLE_NAME dns_dot_block 2>/dev/null || true
EOF
			lpr_nft_render_cleanup "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY"
			;;
		ipset)
			cat <<EOF
iptables -t nat -D PREROUTING -i $LPR_LAN_IF -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -t nat -D PREROUTING -i $LPR_LAN_IF -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -D FORWARD -i $LPR_LAN_IF -p tcp --dport 853 -j REJECT 2>/dev/null || true
EOF
			lpr_ipset_render_cleanup "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_LAN_IF"
			;;
	esac
}

lpr_service_cleanup() {
	backend="$(lpr_detect_backend "$LPR_BACKEND" 2>/dev/null || printf '%s\n' ipset)"

	lpr_service_render_cleanup "$backend" | lpr_service_run_commands
}

lpr_service_apply() {
	lpr_service_validate
	backend="$(lpr_service_backend)"

	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		{
			lpr_service_render_cleanup "$backend"
			lpr_service_render_backend "$backend"
			lpr_service_render_dnsmasq_config "$backend"
			lpr_service_render_dns_firewall "$backend"
		} | lpr_service_run_commands
		return 0
	fi

	lpr_service_render_cleanup "$backend" | lpr_service_run_commands
	lpr_service_render_backend "$backend" | lpr_service_run_commands
	lpr_service_write_dnsmasq_config "$backend"
	lpr_service_render_dns_firewall "$backend" | lpr_service_run_commands
}

lpr_service_diagnose() {
	backend="$(lpr_service_backend)"
	printf '{"backend":"%s","dns_mode":"%s","lan_if":"%s","table":"%s","mark":"%s"}\n' \
		"$backend" "$LPR_DNS_MODE" "$LPR_LAN_IF" "$LPR_TABLE" "$LPR_MARK"
}

cmd="${1:-render}"
case "$cmd" in
	validate)
		lpr_service_validate
		;;
	render)
		lpr_service_validate
		lpr_service_render
		;;
	apply)
		lpr_service_apply
		;;
	cleanup|stop)
		lpr_service_cleanup
		;;
	diagnose)
		lpr_service_validate
		lpr_service_diagnose
		;;
	*)
		lpr_die "usage: $0 validate|render|apply|cleanup|diagnose"
		;;
esac
