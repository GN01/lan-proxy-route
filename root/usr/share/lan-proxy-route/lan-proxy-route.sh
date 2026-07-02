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
. "$BASE_DIR/diagnostics.sh"

LPR_ROUTER_IP="${LPR_ROUTER_IP:-192.168.1.1}"
LPR_DNSMASQ_CONF="${LPR_DNSMASQ_CONF:-/tmp/dnsmasq.d/lan-proxy-route.conf}"
LPR_ETC_DIR="${LPR_ETC_DIR:-/etc/lan-proxy-route}"
if [ -d "./root/etc/lan-proxy-route" ]; then
	LPR_ETC_DIR="./root/etc/lan-proxy-route"
fi
LPR_CONFIG="${LPR_CONFIG:-/etc/config/lan_proxy_route}"
LPR_STATE_FILE="${LPR_STATE_FILE:-/var/run/lan-proxy-route.state}"

lpr_join_lines() {
	existing="${1:-}"
	value="${2:-}"
	[ -n "$value" ] || {
		printf '%s' "$existing"
		return 0
	}
	if [ -n "$existing" ]; then
		printf '%s\n%s' "$existing" "$value"
	else
		printf '%s' "$value"
	fi
}

lpr_first_line() {
	first_line=
	while IFS= read -r first_line; do
		break
	done <<EOF
${1:-}
EOF
	printf '%s\n' "$first_line"
}

lpr_default_list_specs() {
	lpr_join_lines "" "$LPR_ETC_DIR/adblock.txt:adblock:real-ip:domestic"
	printf '\n%s' "$LPR_ETC_DIR/gfwlist.txt:proxy:$LPR_CFG_DNS_MODE:proxy"
	printf '\n%s' "$LPR_ETC_DIR/custom-proxy-domains.txt:proxy:$LPR_CFG_DNS_MODE:proxy"
	printf '\n%s' "$LPR_ETC_DIR/custom-bypass-domains.txt:bypass:real-ip:domestic"
}

lpr_config_finish_list_section() {
	[ "${LPR_UCI_SECTION_TYPE:-}" = "list" ] || return 0
	[ "${LPR_UCI_LIST_ENABLED:-1}" = "1" ] || return 0
	[ -n "${LPR_UCI_LIST_SOURCE:-}" ] || return 0

	role="${LPR_UCI_LIST_ROLE:-proxy}"
	dns_result="${LPR_UCI_LIST_DNS_RESULT:-$LPR_CFG_DNS_MODE}"
	dns_upstream="${LPR_UCI_LIST_DNS_UPSTREAM:-proxy}"
	LPR_CFG_LIST_SPECS="$(lpr_join_lines "$LPR_CFG_LIST_SPECS" "$LPR_UCI_LIST_SOURCE:$role:$dns_result:$dns_upstream")"
	if [ "$role" = "proxy" ] && [ "$dns_result" = "fake-ip" ]; then
		LPR_CFG_HAS_FAKE_LIST=1
	fi
}

lpr_config_start_section() {
	lpr_config_finish_list_section
	LPR_UCI_SECTION_TYPE="$1"
	LPR_UCI_SECTION_NAME="${2:-}"
	LPR_UCI_LIST_ENABLED=1
	LPR_UCI_LIST_ROLE=proxy
	LPR_UCI_LIST_SOURCE=
	LPR_UCI_LIST_DNS_RESULT=
	LPR_UCI_LIST_DNS_UPSTREAM=proxy
}

lpr_config_set_value() {
	keyword="$1"
	key="$2"
	value="$3"

	case "$LPR_UCI_SECTION_TYPE:$keyword:$key" in
		global:option:enabled) LPR_CFG_ENABLED="$value" ;;
		global:option:backend) LPR_CFG_BACKEND="$value" ;;
		global:option:dns_mode) LPR_CFG_DNS_MODE="$value" ;;
		global:option:mark) LPR_CFG_MARK="$value" ;;
		global:option:table) LPR_CFG_TABLE="$value" ;;
		global:option:priority) LPR_CFG_PRIORITY="$value" ;;
		global:option:lan_if) LPR_CFG_LAN_IF="$value" ;;
		global:option:fake_ip_cidr) LPR_CFG_FAKE_CIDR="$value" ;;
		proxy_node:option:ip)
			[ "$LPR_UCI_SECTION_NAME" = "x86" ] && LPR_CFG_X86_IP="$value"
			;;
		proxy_node:option:dns_port)
			[ "$LPR_UCI_SECTION_NAME" = "x86" ] && LPR_CFG_X86_DNS_PORT="$value"
			;;
		dns:option:hijack_53) LPR_CFG_HIJACK_53="$value" ;;
		dns:option:block_dot) LPR_CFG_BLOCK_DOT="$value" ;;
		dns:list:domestic_dns) LPR_CFG_DOMESTIC_DNS="$(lpr_join_lines "$LPR_CFG_DOMESTIC_DNS" "$value")" ;;
		dns:list:proxy_dns) LPR_CFG_PROXY_DNS_LIST="$(lpr_join_lines "$LPR_CFG_PROXY_DNS_LIST" "$value")" ;;
		access:option:mode) LPR_CFG_ACCESS_MODE="$value" ;;
		access:list:allow_ip) LPR_CFG_ALLOW_IPS="$(lpr_join_lines "$LPR_CFG_ALLOW_IPS" "$value")" ;;
		access:list:allow_cidr) LPR_CFG_ALLOW_CIDRS="$(lpr_join_lines "$LPR_CFG_ALLOW_CIDRS" "$value")" ;;
		access:list:block_ip) LPR_CFG_BLOCK_IPS="$(lpr_join_lines "$LPR_CFG_BLOCK_IPS" "$value")" ;;
		access:list:block_cidr) LPR_CFG_BLOCK_CIDRS="$(lpr_join_lines "$LPR_CFG_BLOCK_CIDRS" "$value")" ;;
		bypass:list:cidr|bypass:list:host) LPR_CFG_BYPASS_CIDRS="$(lpr_join_lines "$LPR_CFG_BYPASS_CIDRS" "$value")" ;;
		list:option:enabled) LPR_UCI_LIST_ENABLED="$value" ;;
		list:option:role) LPR_UCI_LIST_ROLE="$value" ;;
		list:option:source) LPR_UCI_LIST_SOURCE="$value" ;;
		list:option:dns_result) LPR_UCI_LIST_DNS_RESULT="$value" ;;
		list:option:dns_upstream) LPR_UCI_LIST_DNS_UPSTREAM="$value" ;;
	esac
}

lpr_config_parse_line() {
	line="$(lpr_trim_line "$1")"
	case "$line" in
		''|\#*) return 0 ;;
	esac

	case "$line" in
		config*)
			rest="$(lpr_trim_line "${line#config}")"
			section_type="${rest%%[	 ]*}"
			if [ "$section_type" = "$rest" ]; then
				section_name=
			else
				section_name="$(lpr_strip_quotes "${rest#"$section_type"}")"
			fi
			lpr_config_start_section "$section_type" "$section_name"
			;;
		option*|list*)
			keyword="${line%%[	 ]*}"
			rest="$(lpr_trim_line "${line#"$keyword"}")"
			key="${rest%%[	 ]*}"
			[ "$key" != "$rest" ] || return 0
			value="$(lpr_strip_quotes "${rest#"$key"}")"
			lpr_config_set_value "$keyword" "$key" "$value"
			;;
	esac
}

lpr_load_config() {
	LPR_CFG_ENABLED=1
	LPR_CFG_BACKEND=auto
	LPR_CFG_DNS_MODE=real-ip
	LPR_CFG_MARK=0x210
	LPR_CFG_TABLE=210
	LPR_CFG_PRIORITY=10210
	LPR_CFG_LAN_IF=br-lan
	LPR_CFG_X86_IP=192.168.1.2
	LPR_CFG_X86_DNS_PORT=53
	LPR_CFG_FAKE_CIDR=198.18.0.0/15
	LPR_CFG_ACCESS_MODE=all
	LPR_CFG_HIJACK_53=1
	LPR_CFG_BLOCK_DOT=1
	LPR_CFG_DOMESTIC_DNS=
	LPR_CFG_PROXY_DNS_LIST=
	LPR_CFG_ALLOW_IPS=
	LPR_CFG_ALLOW_CIDRS=
	LPR_CFG_BLOCK_IPS=
	LPR_CFG_BLOCK_CIDRS=
	LPR_CFG_BYPASS_CIDRS=
	LPR_CFG_LIST_SPECS=
	LPR_CFG_HAS_FAKE_LIST=0
	LPR_UCI_SECTION_TYPE=
	LPR_UCI_SECTION_NAME=

	if [ -f "$LPR_CONFIG" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			lpr_config_parse_line "$line"
		done < "$LPR_CONFIG"
		lpr_config_finish_list_section
	fi

	if [ -z "$LPR_CFG_DOMESTIC_DNS" ]; then
		LPR_CFG_DOMESTIC_DNS="$(lpr_join_lines "$LPR_CFG_DOMESTIC_DNS" 114.114.114.114)"
		LPR_CFG_DOMESTIC_DNS="$(lpr_join_lines "$LPR_CFG_DOMESTIC_DNS" 223.5.5.5)"
	fi
	if [ -z "$LPR_CFG_PROXY_DNS_LIST" ]; then
		LPR_CFG_PROXY_DNS_LIST="$LPR_CFG_X86_IP#$LPR_CFG_X86_DNS_PORT"
	fi
	if [ -z "$LPR_CFG_LIST_SPECS" ]; then
		LPR_CFG_LIST_SPECS="$(lpr_default_list_specs)"
	fi

	[ "${LPR_ENABLED+x}" ] && LPR_CFG_ENABLED="$LPR_ENABLED"
	[ "${LPR_BACKEND+x}" ] && LPR_CFG_BACKEND="$LPR_BACKEND"
	[ "${LPR_DNS_MODE+x}" ] && LPR_CFG_DNS_MODE="$LPR_DNS_MODE"
	[ "${LPR_MARK+x}" ] && LPR_CFG_MARK="$LPR_MARK"
	[ "${LPR_TABLE+x}" ] && LPR_CFG_TABLE="$LPR_TABLE"
	[ "${LPR_PRIORITY+x}" ] && LPR_CFG_PRIORITY="$LPR_PRIORITY"
	[ "${LPR_LAN_IF+x}" ] && LPR_CFG_LAN_IF="$LPR_LAN_IF"
	[ "${LPR_X86_IP+x}" ] && LPR_CFG_X86_IP="$LPR_X86_IP"
	[ "${LPR_PROXY_DNS+x}" ] && LPR_CFG_PROXY_DNS_LIST="$LPR_PROXY_DNS"
	[ "${LPR_FAKE_CIDR+x}" ] && LPR_CFG_FAKE_CIDR="$LPR_FAKE_CIDR"
	[ "${LPR_ACCESS_MODE+x}" ] && LPR_CFG_ACCESS_MODE="$LPR_ACCESS_MODE"
	[ "${LPR_HIJACK_53+x}" ] && LPR_CFG_HIJACK_53="$LPR_HIJACK_53"
	[ "${LPR_BLOCK_DOT+x}" ] && LPR_CFG_BLOCK_DOT="$LPR_BLOCK_DOT"

	LPR_ENABLED="$LPR_CFG_ENABLED"
	LPR_BACKEND="$LPR_CFG_BACKEND"
	LPR_DNS_MODE="$LPR_CFG_DNS_MODE"
	LPR_MARK="$LPR_CFG_MARK"
	LPR_TABLE="$LPR_CFG_TABLE"
	LPR_PRIORITY="$LPR_CFG_PRIORITY"
	LPR_LAN_IF="$LPR_CFG_LAN_IF"
	LPR_X86_IP="$LPR_CFG_X86_IP"
	LPR_PROXY_DNS_LIST="$LPR_CFG_PROXY_DNS_LIST"
	LPR_PROXY_DNS="$(lpr_first_line "$LPR_PROXY_DNS_LIST")"
	LPR_FAKE_CIDR="$LPR_CFG_FAKE_CIDR"
	LPR_ACCESS_MODE="$LPR_CFG_ACCESS_MODE"
	LPR_HIJACK_53="$LPR_CFG_HIJACK_53"
	LPR_BLOCK_DOT="$LPR_CFG_BLOCK_DOT"
	LPR_DOMESTIC_DNS="$LPR_CFG_DOMESTIC_DNS"
	LPR_ALLOW_IPS="$LPR_CFG_ALLOW_IPS"
	LPR_ALLOW_CIDRS="$LPR_CFG_ALLOW_CIDRS"
	LPR_BLOCK_IPS="$LPR_CFG_BLOCK_IPS"
	LPR_BLOCK_CIDRS="$LPR_CFG_BLOCK_CIDRS"
	LPR_BYPASS_CIDRS="$LPR_CFG_BYPASS_CIDRS"
	LPR_LIST_SPECS="$LPR_CFG_LIST_SPECS"
	LPR_HAS_FAKE_LIST="$LPR_CFG_HAS_FAKE_LIST"
}

lpr_load_config

lpr_service_backend() {
	lpr_detect_backend "$LPR_BACKEND" || lpr_die "unable to detect backend"
}

lpr_service_dns_mode_for_backend() {
	if [ "$LPR_DNS_MODE" = "fake-ip" ] || [ "$LPR_HAS_FAKE_LIST" = "1" ]; then
		printf '%s\n' fake-ip
	else
		printf '%s\n' "$LPR_DNS_MODE"
	fi
}

lpr_service_domestic_dns_csv() {
	first=1
	for dns in $LPR_DOMESTIC_DNS; do
		if [ "$first" -eq 1 ]; then
			printf '%s' "$dns"
			first=0
		else
			printf ',%s' "$dns"
		fi
	done
}

lpr_service_bypass_values() {
	for value in $LPR_BYPASS_CIDRS; do
		printf '%s\n' "$value"
	done
	printf '%s\n' "$LPR_X86_IP"
	for dns in $LPR_DOMESTIC_DNS $LPR_PROXY_DNS_LIST; do
		printf '%s\n' "$(lpr_dns_server_ip "$dns")"
	done
}

lpr_service_render_set_elements() {
	backend="$1"
	bypass_values="$(lpr_service_bypass_values)"

	case "$backend" in
		nftset)
			lpr_nft_render_elements clients_v4 $LPR_ALLOW_IPS $LPR_ALLOW_CIDRS
			lpr_nft_render_elements blocked_clients_v4 $LPR_BLOCK_IPS $LPR_BLOCK_CIDRS
			lpr_nft_render_elements bypass_v4 $bypass_values
			;;
		ipset)
			lpr_ipset_render_elements lpr_clients $LPR_ALLOW_IPS $LPR_ALLOW_CIDRS
			lpr_ipset_render_elements lpr_blocked_clients $LPR_BLOCK_IPS $LPR_BLOCK_CIDRS
			lpr_ipset_render_elements lpr_bypass_v4 $bypass_values
			;;
	esac
}

lpr_service_validate() {
	lpr_is_bool_flag "$LPR_ENABLED" || lpr_die "invalid enabled flag: $LPR_ENABLED"
	lpr_is_ipv4 "$LPR_X86_IP" || lpr_die "invalid proxy IP: $LPR_X86_IP"
	lpr_is_mark "$LPR_MARK" || lpr_die "invalid mark: $LPR_MARK"
	lpr_is_uint "$LPR_TABLE" || lpr_die "invalid table: $LPR_TABLE"
	lpr_is_uint "$LPR_PRIORITY" || lpr_die "invalid priority: $LPR_PRIORITY"
	lpr_is_ifname "$LPR_LAN_IF" || lpr_die "invalid LAN interface: $LPR_LAN_IF"
	lpr_is_cidr "$LPR_FAKE_CIDR" || lpr_die "invalid fake IP CIDR: $LPR_FAKE_CIDR"
	for dns in $LPR_PROXY_DNS_LIST; do
		lpr_is_dns_server "$dns" || lpr_die "invalid proxy DNS: $dns"
	done
	for dns in $LPR_DOMESTIC_DNS; do
		lpr_is_dns_server "$dns" || lpr_die "invalid domestic DNS: $dns"
	done
	lpr_is_ipv4 "$LPR_ROUTER_IP" || lpr_die "invalid router IP: $LPR_ROUTER_IP"

	case "$LPR_DNS_MODE" in
		real-ip|fake-ip|mixed) ;;
		*) lpr_die "invalid DNS mode: $LPR_DNS_MODE" ;;
	esac
	case "$LPR_ACCESS_MODE" in
		all|allowlist|blocklist) ;;
		*) lpr_die "invalid access mode: $LPR_ACCESS_MODE" ;;
	esac
	lpr_is_bool_flag "$LPR_HIJACK_53" || lpr_die "invalid hijack_53 flag: $LPR_HIJACK_53"
	lpr_is_bool_flag "$LPR_BLOCK_DOT" || lpr_die "invalid block_dot flag: $LPR_BLOCK_DOT"

	for value in $LPR_ALLOW_IPS $LPR_BLOCK_IPS; do
		lpr_is_ipv4 "$value" || lpr_die "invalid access IP: $value"
	done
	for value in $LPR_ALLOW_CIDRS $LPR_BLOCK_CIDRS; do
		lpr_is_cidr "$value" || lpr_die "invalid access CIDR: $value"
	done
	for value in $LPR_BYPASS_CIDRS; do
		if ! lpr_is_ipv4 "$value" && ! lpr_is_cidr "$value"; then
			lpr_die "invalid bypass value: $value"
		fi
	done

	if [ "$LPR_ENABLED" = "1" ]; then
		lpr_service_backend >/dev/null
	fi
}

lpr_service_render_backend() {
	backend="$1"
	backend_dns_mode="$(lpr_service_dns_mode_for_backend)"

	case "$backend" in
		nftset)
			lpr_nft_render_table "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$backend_dns_mode" "$LPR_FAKE_CIDR"
			lpr_service_render_set_elements "$backend"
			lpr_nft_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
		ipset)
			lpr_ipset_render_setup
			lpr_ipset_render_elements lpr_clients $LPR_ALLOW_IPS $LPR_ALLOW_CIDRS
			lpr_ipset_render_elements lpr_blocked_clients $LPR_BLOCK_IPS $LPR_BLOCK_CIDRS
			lpr_ipset_render_elements lpr_bypass_v4 $(lpr_service_bypass_values)
			lpr_ipset_render_mangle "$LPR_LAN_IF" "$LPR_MARK" "$LPR_ACCESS_MODE" "$backend_dns_mode" "$LPR_FAKE_CIDR"
			lpr_ipset_render_policy_route "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
			;;
	esac
}

lpr_service_render_dns() {
	backend="$1"

	lpr_dnsmasq_render_config "$backend" "$(lpr_service_domestic_dns_csv)" "$LPR_PROXY_DNS" $LPR_LIST_SPECS
	lpr_dns_render_firewall "$backend" "$LPR_LAN_IF" "$LPR_ROUTER_IP" "$LPR_HIJACK_53" "$LPR_BLOCK_DOT"
}

lpr_service_render_dnsmasq_config() {
	backend="$1"

	lpr_dnsmasq_render_config "$backend" "$(lpr_service_domestic_dns_csv)" "$LPR_PROXY_DNS" $LPR_LIST_SPECS
}

lpr_service_render_dns_firewall() {
	backend="$1"
	lpr_dns_render_firewall "$backend" "$LPR_LAN_IF" "$LPR_ROUTER_IP" "$LPR_HIJACK_53" "$LPR_BLOCK_DOT"
}

lpr_service_render() {
	[ "$LPR_ENABLED" = "1" ] || return 0
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

lpr_service_render_cleanup_tuple() {
	backend="$1"
	mark="$2"
	table="$3"
	priority="$4"
	x86_ip="$5"
	lan_if="$6"

	case "$backend" in
		nftset)
			cat <<EOF
nft flush chain inet $LPR_TABLE_NAME dns_hijack 2>/dev/null || true
nft delete chain inet $LPR_TABLE_NAME dns_hijack 2>/dev/null || true
nft flush chain inet $LPR_TABLE_NAME dns_dot_block 2>/dev/null || true
nft delete chain inet $LPR_TABLE_NAME dns_dot_block 2>/dev/null || true
EOF
			lpr_nft_render_cleanup "$mark" "$table" "$priority" "$x86_ip" "$lan_if"
			;;
		ipset)
			cat <<EOF
iptables -t nat -D PREROUTING -i $lan_if -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -t nat -D PREROUTING -i $lan_if -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -D FORWARD -i $lan_if -p tcp --dport 853 -j REJECT 2>/dev/null || true
EOF
			lpr_ipset_render_cleanup "$mark" "$table" "$priority" "$lan_if" "$x86_ip"
			;;
	esac
}

lpr_service_render_cleanup() {
	backend="$1"
	lpr_service_render_cleanup_tuple "$backend" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF"
}

lpr_service_state_tuple() {
	backend="$1"
	mark="$2"
	table="$3"
	priority="$4"
	x86_ip="$5"
	lan_if="$6"

	cat <<EOF
backend=$backend
mark=$mark
table=$table
priority=$priority
x86_ip=$x86_ip
lan_if=$lan_if
EOF
}

lpr_service_state_reset() {
	LPR_STATE_BACKEND=
	LPR_STATE_MARK=
	LPR_STATE_TABLE=
	LPR_STATE_PRIORITY=
	LPR_STATE_X86_IP=
	LPR_STATE_LAN_IF=
}

lpr_service_state_valid() {
	case "$LPR_STATE_BACKEND" in
		nftset|ipset) ;;
		*) return 1 ;;
	esac
	lpr_is_mark "$LPR_STATE_MARK" || return 1
	lpr_is_uint "$LPR_STATE_TABLE" || return 1
	lpr_is_uint "$LPR_STATE_PRIORITY" || return 1
	lpr_is_ipv4 "$LPR_STATE_X86_IP" || return 1
	lpr_is_ifname "$LPR_STATE_LAN_IF" || return 1
}

lpr_service_load_state() {
	state_file="$1"
	lpr_service_state_reset
	[ -f "$state_file" ] || return 1

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			backend=*) LPR_STATE_BACKEND="${line#backend=}" ;;
			mark=*) LPR_STATE_MARK="${line#mark=}" ;;
			table=*) LPR_STATE_TABLE="${line#table=}" ;;
			priority=*) LPR_STATE_PRIORITY="${line#priority=}" ;;
			x86_ip=*) LPR_STATE_X86_IP="${line#x86_ip=}" ;;
			lan_if=*) LPR_STATE_LAN_IF="${line#lan_if=}" ;;
		esac
	done < "$state_file"

	lpr_service_state_valid
}

lpr_service_render_cleanup_with_state() {
	backend="$1"
	lpr_service_render_cleanup "$backend"

	if lpr_service_load_state "$LPR_STATE_FILE"; then
		current_state="$(lpr_service_state_tuple "$backend" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF")"
		previous_state="$(lpr_service_state_tuple "$LPR_STATE_BACKEND" "$LPR_STATE_MARK" "$LPR_STATE_TABLE" "$LPR_STATE_PRIORITY" "$LPR_STATE_X86_IP" "$LPR_STATE_LAN_IF")"
		if [ "$current_state" != "$previous_state" ]; then
			lpr_service_render_cleanup_tuple "$LPR_STATE_BACKEND" "$LPR_STATE_MARK" "$LPR_STATE_TABLE" "$LPR_STATE_PRIORITY" "$LPR_STATE_X86_IP" "$LPR_STATE_LAN_IF"
		fi
	fi
}

lpr_service_write_state() {
	backend="$1"
	state_dir="$(dirname "$LPR_STATE_FILE")"
	[ -d "$state_dir" ] || mkdir -p "$state_dir"
	lpr_service_state_tuple "$backend" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "$LPR_X86_IP" "$LPR_LAN_IF" > "$LPR_STATE_FILE"
}

lpr_service_cleanup() {
	backend="$(lpr_detect_backend "$LPR_BACKEND" 2>/dev/null || printf '%s\n' ipset)"

	lpr_service_render_cleanup_with_state "$backend" | lpr_service_run_commands

	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		printf 'rm -f %s 2>/dev/null || true\n' "$LPR_DNSMASQ_CONF"
		printf 'rm -f %s 2>/dev/null || true\n' "$LPR_STATE_FILE"
	else
		rm -f "$LPR_DNSMASQ_CONF" 2>/dev/null || true
		rm -f "$LPR_STATE_FILE" 2>/dev/null || true
	fi
}

lpr_service_apply() {
	lpr_service_validate
	if [ "$LPR_ENABLED" != "1" ]; then
		lpr_service_cleanup
		return 0
	fi
	backend="$(lpr_service_backend)"

	if [ "${LPR_DRY_RUN:-0}" = "1" ]; then
		{
			lpr_service_render_cleanup_with_state "$backend"
			lpr_service_render_backend "$backend"
			lpr_service_render_dnsmasq_config "$backend"
			lpr_service_render_dns_firewall "$backend"
		} | lpr_service_run_commands
		return 0
	fi

	lpr_service_render_cleanup_with_state "$backend" | lpr_service_run_commands
	lpr_service_render_backend "$backend" | lpr_service_run_commands
	lpr_service_write_dnsmasq_config "$backend"
	lpr_service_render_dns_firewall "$backend" | lpr_service_run_commands
	lpr_service_write_state "$backend"
}

lpr_service_test_route() {
	dst="${1:-8.8.8.8}"
	lpr_is_ipv4 "$dst" || lpr_die "invalid destination IP: $dst"

	if ! command -v ip >/dev/null 2>&1; then
		printf '{"ok":false,"matched":false,"reason":"ip command unavailable"}\n'
		return 1
	fi

	if route_out="$(ip route get "$dst" mark "$LPR_MARK" 2>/dev/null)"; then
		case "$route_out" in
			*" via $LPR_X86_IP "*|*" via $LPR_X86_IP")
				case "$route_out" in
					*" dev $LPR_LAN_IF "*|*" dev $LPR_LAN_IF"|*" dev $LPR_LAN_IF "*) matched=true ;;
					*) matched=false ;;
				esac
				;;
			*) matched=false ;;
		esac
		printf '{"ok":true,"matched":%s,"dst":"%s","mark":"%s"}\n' "$matched" "$dst" "$LPR_MARK"
	else
		printf '{"ok":false,"matched":false,"dst":"%s","mark":"%s","reason":"route lookup failed"}\n' "$dst" "$LPR_MARK"
		return 1
	fi
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
		if backend="$(lpr_detect_backend "$LPR_BACKEND" 2>/dev/null)"; then
			lpr_diag_json "$backend" "$LPR_X86_IP" "$LPR_LAN_IF" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" "" "$LPR_DNSMASQ_CONF"
		else
			lpr_diag_json "unknown" "$LPR_X86_IP" "$LPR_LAN_IF" "$LPR_MARK" "$LPR_TABLE" "$LPR_PRIORITY" \
				"unable to detect backend" "$LPR_DNSMASQ_CONF"
		fi
		;;
	test-route)
		lpr_service_validate
		lpr_service_test_route "${2:-8.8.8.8}"
		;;
	*)
		lpr_die "usage: $0 validate|render|apply|cleanup|diagnose|test-route"
		;;
esac
